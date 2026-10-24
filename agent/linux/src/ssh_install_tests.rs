//! `install_sshd` on top of the SSH keys call: the fixed script, its report, the request flag, the failure answers, the order of the two `incus exec` calls and the time limits.
//! The script is also run once under a throwaway root (every path rewritten into a temp folder, a stub `sshd`), so its config logic is exercised without touching a real system.
use crate::cpu::CpuOffer;
use crate::engine::SimulatedInstall;
use crate::incus::{IncusEngine, Runner};
use crate::models::*;
use crate::service::Failure;
use crate::ssh_install::{self, InstallReport, SshdFailure, INSTALL_SCRIPT};
use crate::ssh_keys::{self, SshRequest, Sshd};
use crate::ssh_keys_tests::{body_of, keys, machine, send, service_over, KEY, TOKEN};
use axum::http::StatusCode;
use serde_json::{json, Value};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::time::Duration;

const PATH_KEYS: &str = "/v1/workloads/w-1/ssh-keys";
const INSTALL_LIMIT: Duration = Duration::from_secs(300);
const PLAIN_LIMIT: Duration = Duration::from_secs(30);
/// What the plain (no install) script was before this feature; it must not change by a byte.
const PLAIN_SCRIPT: &str = "set -e
umask 077
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys.new
chmod 600 /root/.ssh/authorized_keys.new
mv -f /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys
if cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; then
  echo sshd=running
elif command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; then
  echo sshd=installed
else
  echo sshd=missing
fi
";

fn at(needle: &str) -> usize {
    INSTALL_SCRIPT.find(needle).unwrap_or_else(|| panic!("the install script has no {needle:?}"))
}

fn install_body(install: Value) -> String {
    json!({ "keys": [KEY], "install_sshd": install }).to_string()
}

// ---- the script text

#[test]
fn the_plain_script_is_unchanged_byte_for_byte() {
    assert_eq!(ssh_keys::SCRIPT, PLAIN_SCRIPT);
}

#[test]
fn the_install_script_is_valid_shell_text() {
    let status = Command::new("/bin/sh").args(["-n", "-c", INSTALL_SCRIPT]).status().unwrap();
    assert!(status.success());
}

#[test]
fn the_call_is_a_fixed_exec_of_the_constant_with_no_request_data() {
    assert_eq!(ssh_install::incus_call("ms-w-1"), ["exec", "ms-w-1", "--", "/bin/sh", "-c", INSTALL_SCRIPT]);
    assert!(!INSTALL_SCRIPT.contains("authorized_keys") && !INSTALL_SCRIPT.contains("ssh-ed25519"), "no key handling in the install script");
}

#[test]
fn the_config_is_exactly_the_four_key_only_lines_in_a_drop_in() {
    for line in ["PasswordAuthentication no\n", "KbdInteractiveAuthentication no\n", "PermitRootLogin prohibit-password\n", "PubkeyAuthentication yes\n"] {
        assert_eq!(INSTALL_SCRIPT.matches(line).count(), 1, "{line}");
    }
    let block = "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\nEOF";
    assert!(INSTALL_SCRIPT.contains(block), "the four lines, in this order, and nothing else");
    for needle in ["/etc/ssh/sshd_config.d/10-metaservice.conf", "# BEGIN metaservice", "# END metaservice", "Include", "sshd -t"] {
        assert!(INSTALL_SCRIPT.contains(needle), "{needle}");
    }
}

#[test]
fn package_managers_are_tried_in_order_apt_apk_dnf_yum_and_only_the_install_script_installs() {
    let order = ["command -v apt-get", "command -v apk", "command -v dnf", "command -v yum"].map(at);
    assert!(order.windows(2).all(|pair| pair[0] < pair[1]), "{order:?}");
    for command in ["DEBIAN_FRONTEND=noninteractive apt-get update", "DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server", "apk add --no-cache openssh", "dnf -y install openssh-server", "yum -y install openssh-server"] {
        assert!(INSTALL_SCRIPT.contains(command), "{command}");
    }
    for plain_word in ["apt-get", "apk add", "dnf", "yum", "systemctl", "ssh-keygen"] {
        assert!(!ssh_keys::SCRIPT.contains(plain_word), "the keys script must not touch {plain_word}");
    }
}

#[test]
fn it_looks_for_the_failures_by_code_and_starts_the_server_by_systemd_or_plainly() {
    for code in ["no_package_manager", "install_failed", "config_invalid", "not_listening"] {
        assert!(INSTALL_SCRIPT.contains(code), "{code}");
        assert!(SshdFailure::from_code(code).is_some(), "{code}");
    }
    for needle in ["systemctl enable --now", "systemctl reload", "/run/systemd/system", "kill -HUP", "ssh-keygen -A", "mkdir -p /run/sshd", "/proc/net/tcp6", ":0016"] {
        assert!(INSTALL_SCRIPT.contains(needle), "{needle}");
    }
    assert!(at("has_sshd || ensure_package") < at("apply_config\nstart_server"), "install before config before start");
}

// ---- the report

#[test]
fn the_report_is_read_and_nothing_is_guessed() {
    let ok = parse_report("sshd=running\ninstalled=true\n");
    assert_eq!(ok, Some(InstallReport { sshd: Sshd::Running, installed: true, failure: None }));
    assert_eq!(parse_report("apt noise\nsshd=installed\ninstalled=false\nfailure=not_listening\n").unwrap().failure, Some(SshdFailure::NotListening));
    assert_eq!(parse_report("sshd=missing\n").unwrap().installed, false, "no installed line means not installed");
    for bad in ["", "installed=true\n", "sshd=maybe\n", "sshd=running\nfailure=oops\n"] {
        assert_eq!(parse_report(bad), None, "{bad:?}");
    }
}

fn parse_report(text: &str) -> Option<InstallReport> {
    ssh_install::parse_report(text)
}

#[test]
fn every_failure_has_its_plain_message() {
    let expected = [
        (SshdFailure::NoPackageManager, "The VM has no package manager the helper knows (apt, apk, dnf, yum), so it cannot install the SSH server."),
        (SshdFailure::InstallFailed, "The VM could not download the SSH server. Check that the VM has internet access."),
        (SshdFailure::ConfigInvalid, "The SSH server did not accept its settings, so nothing was changed."),
        (SshdFailure::NotListening, "The SSH server was installed but is not listening on port 22."),
    ];
    for (failure, message) in expected {
        assert_eq!(failure.message(), message);
    }
}

// ---- the request

#[test]
fn install_sshd_is_a_boolean_that_defaults_to_false() {
    let parse = |text: String| SshRequest::parse(text.as_bytes());
    assert!(!parse(body_of(&[KEY])).unwrap().install_sshd);
    assert!(parse(install_body(json!(true))).unwrap().install_sshd);
    assert!(!parse(install_body(json!(false))).unwrap().install_sshd);
    for wrong in [json!("yes"), json!(1), json!(null), json!(["true"])] {
        assert!(parse(install_body(wrong.clone())).is_err(), "{wrong}");
    }
    assert!(parse(json!({"keys": [KEY], "install": true}).to_string()).is_err(), "other unknown fields stay refused");
}

// ---- service and route over the simulated engine

#[tokio::test]
async fn a_missing_sshd_is_installed_once_and_the_second_call_installs_nothing() {
    let (engine, service) = machine();
    engine.set_sshd(Sshd::Missing);
    let request = || SshRequest { install_sshd: true, ..keys(&[KEY]) };
    let first = service.apply_ssh_keys("w-1", request()).await.ok().unwrap();
    assert_eq!((first.applied, first.sshd, first.installed), (1, Sshd::Running, Some(true)));
    let second = service.apply_ssh_keys("w-1", request()).await.ok().unwrap();
    assert_eq!((second.sshd, second.installed), (Sshd::Running, Some(false)));
}

#[tokio::test]
async fn the_plain_call_never_asks_for_an_install() {
    let (engine, service) = machine();
    let done = service.apply_ssh_keys("w-1", keys(&[KEY])).await.ok().unwrap();
    assert_eq!((done.sshd, done.installed), (Sshd::Missing, None));
    assert_eq!(engine.install_calls(), 0);
}

#[tokio::test]
async fn a_failed_install_is_a_failure_and_the_keys_are_still_written() {
    let (engine, service) = machine();
    engine.set_install(SimulatedInstall::Fails(SshdFailure::InstallFailed));
    let result = service.apply_ssh_keys("w-1", SshRequest { install_sshd: true, ..keys(&[KEY]) }).await;
    assert!(matches!(result, Err(Failure::Sshd(SshdFailure::InstallFailed))));
    assert_eq!(engine.written_ssh_keys("w-1").unwrap(), format!("{KEY}\n").into_bytes());
}

#[tokio::test]
async fn the_route_answers_200_with_installed_only_when_asked() {
    let (_, service) = machine();
    let (status, answer) = send(&service, "PUT", PATH_KEYS, &install_body(json!(true)), TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, json!({"applied": 1, "sshd": "running", "installed": true})));
    let (_, answer) = send(&service, "PUT", PATH_KEYS, &install_body(json!(true)), TOKEN).await;
    assert_eq!(answer, json!({"applied": 1, "sshd": "running", "installed": false}));
    let (_, answer) = send(&service, "PUT", PATH_KEYS, &install_body(json!(false)), TOKEN).await;
    assert_eq!(answer, json!({"applied": 1, "sshd": "running"}), "false is the plain answer");
}

#[tokio::test]
async fn the_route_answers_502_with_the_plain_message_and_keeps_the_keys() {
    let (engine, service) = machine();
    for failure in [SshdFailure::NoPackageManager, SshdFailure::InstallFailed, SshdFailure::ConfigInvalid, SshdFailure::NotListening] {
        engine.set_install(SimulatedInstall::Fails(failure));
        let (status, answer) = send(&service, "PUT", PATH_KEYS, &install_body(json!(true)), TOKEN).await;
        assert_eq!(status, StatusCode::BAD_GATEWAY, "{failure:?}");
        assert_eq!(answer, json!({"error": {"code": "sshd_install_failed", "message": failure.message()}}));
        assert!(!answer.to_string().contains("AAAAC3"), "no key text in the answer");
        assert_eq!(engine.written_ssh_keys("w-1").unwrap(), format!("{KEY}\n").into_bytes());
    }
}

#[tokio::test]
async fn the_route_answers_400_for_a_wrong_install_sshd_type_and_writes_nothing() {
    let (engine, service) = machine();
    for wrong in [json!("yes"), json!(1), json!(null)] {
        let (status, answer) = send(&service, "PUT", PATH_KEYS, &install_body(wrong), TOKEN).await;
        assert_eq!((status, answer["error"]["code"].as_str()), (StatusCode::BAD_REQUEST, Some("invalid_input")));
    }
    assert!(engine.written_ssh_keys("w-1").is_none());
}

// ---- the Incus engine: two calls, in order, with their own time limits

/// Records every `exec` (arguments, input, time limit) and answers the keys call and the install call as told.
struct TwoCalls {
    install_answer: Result<String, String>,
    calls: Mutex<Vec<(Vec<String>, Option<Vec<u8>>, Duration)>>,
}

impl TwoCalls {
    fn new(install_answer: Result<String, String>) -> Arc<Self> {
        Arc::new(TwoCalls { install_answer, calls: Mutex::new(Vec::new()) })
    }

    fn execs(&self) -> Vec<(Vec<String>, Option<Vec<u8>>, Duration)> {
        self.calls.lock().unwrap().iter().filter(|(arguments, _, _)| arguments[0] == "exec").cloned().collect()
    }
}

impl Runner for TwoCalls {
    fn run(&self, arguments: &[String], timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push((arguments.to_vec(), None, timeout));
        if arguments[0] == "exec" {
            return self.install_answer.clone().map_err(EngineError::Failed);
        }
        let instance = json!([{"name": "ms-w-1", "status": "Running", "config": {"user.metaservice.id": "w-1", "user.metaservice.name": "box", "user.metaservice.kind": "vm",
            "user.metaservice.cpu": "1", "user.metaservice.ram_mb": "512", "user.metaservice.disk_gb": "1"}, "state": null}]);
        Ok(instance.to_string())
    }

    fn run_with_input(&self, arguments: &[String], input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push((arguments.to_vec(), Some(input.to_vec()), timeout));
        Ok("sshd=missing\n".into())
    }
}

fn incus_over(runner: Arc<TwoCalls>) -> Arc<crate::service::Service> {
    let capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY, sandbox: false };
    service_over(Arc::new(IncusEngine::new(runner, capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1)))
}

#[tokio::test]
async fn incus_writes_the_keys_first_then_installs_with_the_long_limit_and_no_key_in_any_argument() {
    let runner = TwoCalls::new(Ok("sshd=running\ninstalled=true\n".into()));
    let done = incus_over(runner.clone()).apply_ssh_keys("w-1", SshRequest { install_sshd: true, ..keys(&[KEY]) }).await.ok().unwrap();
    assert_eq!((done.sshd, done.installed), (Sshd::Running, Some(true)));
    let execs = runner.execs();
    assert_eq!(execs.len(), 2);
    assert_eq!((&execs[0].0, execs[0].1.as_deref(), execs[0].2), (&ssh_keys::incus_call("ms-w-1"), Some(format!("{KEY}\n").as_bytes()), PLAIN_LIMIT));
    assert_eq!((&execs[1].0, &execs[1].1, execs[1].2), (&ssh_install::incus_call("ms-w-1"), &None, INSTALL_LIMIT), "the install is its own call without input");
    for (arguments, _, _) in runner.calls.lock().unwrap().iter() {
        assert!(!arguments.iter().any(|part| part.contains("AAAAC3") || part.contains("alice")), "no key text in any command line: {arguments:?}");
    }
}

#[tokio::test]
async fn the_plain_call_on_incus_makes_no_install_call() {
    let runner = TwoCalls::new(Ok(String::new()));
    incus_over(runner.clone()).apply_ssh_keys("w-1", keys(&[KEY])).await.ok().unwrap();
    assert_eq!(runner.execs().len(), 1);
}

#[tokio::test]
async fn a_timeout_or_a_failed_exec_is_install_failed_after_the_keys_were_written() {
    let runner = TwoCalls::new(Err("incus exec took too long".into()));
    let result = incus_over(runner.clone()).apply_ssh_keys("w-1", SshRequest { install_sshd: true, ..keys(&[KEY]) }).await;
    assert!(matches!(result, Err(Failure::Sshd(SshdFailure::InstallFailed))));
    assert_eq!(runner.execs().len(), 2, "the keys call ran before the install that failed");
}

#[tokio::test]
async fn a_script_that_does_not_finish_is_install_failed_and_a_reported_failure_is_passed_on() {
    let silent = incus_over(TwoCalls::new(Ok("garbage\n".into())));
    assert!(matches!(silent.apply_ssh_keys("w-1", SshRequest { install_sshd: true, ..keys(&[KEY]) }).await, Err(Failure::Sshd(SshdFailure::InstallFailed))));
    let refused = incus_over(TwoCalls::new(Ok("sshd=missing\ninstalled=false\nfailure=no_package_manager\n".into())));
    assert!(matches!(refused.apply_ssh_keys("w-1", SshRequest { install_sshd: true, ..keys(&[KEY]) }).await, Err(Failure::Sshd(SshdFailure::NoPackageManager))));
}

// ---- the script under a throwaway root

/// A temp folder with a stub `sshd` (exit code given) and an `sshd_config`; the script is rewritten so every path it touches is inside that folder.
struct Sandbox {
    root: PathBuf,
}

impl Sandbox {
    fn new(sshd_exit: i32, config: &str, with_include: bool) -> Sandbox {
        use std::os::unix::fs::PermissionsExt;
        let root = std::env::temp_dir().join(format!("ms-sshd-box-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("bin")).unwrap();
        std::fs::create_dir_all(root.join("etc/ssh")).unwrap();
        std::fs::write(root.join("bin/sshd"), format!("#!/bin/sh\nexit {sshd_exit}\n")).unwrap();
        std::fs::set_permissions(root.join("bin/sshd"), std::fs::Permissions::from_mode(0o755)).unwrap();
        let include = if with_include { format!("Include {}/etc/ssh/sshd_config.d/*.conf\n", root.display()) } else { String::new() };
        std::fs::write(root.join("etc/ssh/sshd_config"), format!("{include}{config}")).unwrap();
        Sandbox { root }
    }

    fn rewritten_script(&self) -> String {
        let root = self.root.display().to_string();
        let script = INSTALL_SCRIPT
            .replace("/etc/ssh", &format!("{root}/etc/ssh"))
            .replace("/run/", &format!("{root}/run/"))
            .replace("/usr/sbin/sshd", &format!("{root}/bin/sshd"))
            .replace("ssh-keygen -A </dev/null >/dev/null 2>&1", "true")
            .replace("WAIT_TRIES=10", "WAIT_TRIES=0");
        for path in ["/etc/ssh", "/run/", "/usr/sbin/sshd"] {
            assert_eq!(script.matches(path).count(), script.matches(&format!("{root}{path}")).count(), "{path} escaped the sandbox");
        }
        assert!(!script.contains("ssh-keygen -A"), "host keys would be made for real");
        script
    }

    fn run(&self) -> String {
        let path = format!("{}/bin:{}", self.root.display(), std::env::var("PATH").unwrap());
        let output = Command::new("/bin/sh").args(["-c", &self.rewritten_script()]).env("PATH", path).output().unwrap();
        String::from_utf8_lossy(&output.stdout).into_owned()
    }

    fn read(&self, relative: &str) -> Option<String> {
        std::fs::read_to_string(self.root.join(relative)).ok()
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(Path::new(&self.root));
    }
}

const DROP_IN: &str = "etc/ssh/sshd_config.d/10-metaservice.conf";
const MAIN: &str = "etc/ssh/sshd_config";
const FOUR_LINES: &str = "PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nPubkeyAuthentication yes\n";

#[test]
fn with_an_include_line_only_the_drop_in_is_written_and_a_second_run_changes_nothing() {
    let sandbox = Sandbox::new(0, "PasswordAuthentication yes\n", true);
    let before = sandbox.read(MAIN).unwrap();
    let report = sandbox.run();
    assert!(report.contains("installed=false"), "{report}");
    assert_eq!(sandbox.read(DROP_IN).unwrap(), FOUR_LINES);
    assert_eq!(sandbox.read(MAIN).unwrap(), before, "the main file is left alone when it includes the drop-in folder");
    sandbox.run();
    assert_eq!(sandbox.read(DROP_IN).unwrap(), FOUR_LINES);
    assert_eq!(sandbox.read(MAIN).unwrap(), before);
}

#[test]
fn without_an_include_line_a_marked_block_is_added_once_at_the_top() {
    let sandbox = Sandbox::new(0, "Port 22\nPasswordAuthentication yes\n", false);
    sandbox.run();
    let first = sandbox.read(MAIN).unwrap();
    assert_eq!(first, format!("# BEGIN metaservice\n{FOUR_LINES}# END metaservice\nPort 22\nPasswordAuthentication yes\n"));
    sandbox.run();
    assert_eq!(sandbox.read(MAIN).unwrap(), first, "a second run does not duplicate the block");
}

#[test]
fn a_config_sshd_refuses_is_rolled_back_and_reported_as_config_invalid() {
    let sandbox = Sandbox::new(1, "Port 22\n", false);
    let report = sandbox.run();
    assert!(report.contains("failure=config_invalid"), "{report}");
    assert_eq!(sandbox.read(MAIN).unwrap(), "Port 22\n", "the previous file is back");
    assert_eq!(sandbox.read(DROP_IN), None, "the new drop-in is removed");
}
