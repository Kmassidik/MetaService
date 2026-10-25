//! SSH keys per VM, above the rules in `ssh_keys.rs`: the route's status codes, the service, the Incus engine's exact call (a recording runner), and the real
//! process runner with a fake `incus` (standard input, time limit, output limit). Nothing real is touched.
use crate::budget::SpaceBudget;
use crate::cpu::CpuOffer;
use crate::engine::{default_capabilities, Engine, SimulatedEngine};
use crate::http::{router, App};
use crate::incus::{IncusEngine, ProcessRunner, Runner};
use crate::models::*;
use crate::service::{BundleInstalling, Failure, Service};
use crate::ssh_keys::{self, KeyList, SshRequest, Sshd};
use crate::validate::{BundleRequest, CreateRequest};
use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tower::ServiceExt;

pub(crate) const TOKEN: &str = "test-token";
pub(crate) const KEY: &str = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01 alice@laptop";
const TIME_LIMIT: Duration = Duration::from_secs(5);

struct NoChat;

impl BundleInstalling for NoChat {
    fn install(&self, _request: &BundleRequest) -> Result<HashMap<String, String>, String> {
        Ok(HashMap::new())
    }

    fn uninstall(&self, _workload_id: Option<&str>) -> Result<(), String> {
        Ok(())
    }

    fn installed_version(&self) -> Option<String> {
        None
    }
}

fn specs() -> Specs {
    Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, cpu_model: None, ram_total_mb: 65536, disk_total_gb: 2000, gpu: Vec::new(), hardware: None }
}

pub(crate) fn service_over(engine: Arc<dyn Engine>) -> Arc<Service> {
    Arc::new(Service::new(engine, SpaceBudget::new(65536, 2000), specs(), "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), Arc::new(NoChat), || None))
}

fn vm_request(command_id: &str) -> CreateRequest {
    CreateRequest { command_id: command_id.into(), name: "box".into(), kind: Kind::Vm, cpu: 2, ram_mb: 2048, disk_gb: 10, gpu_mode: GpuMode::None, image: None, gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None }
}

/// A simulated machine with one running VM called `w-1`.
pub(crate) fn machine() -> (Arc<SimulatedEngine>, Arc<Service>) {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create("w-1", &vm_request("c-1")).ok().unwrap();
    let service = service_over(engine.clone());
    (engine, service)
}

pub(crate) fn keys(lines: &[&str]) -> SshRequest {
    SshRequest { keys: KeyList::from_lines(lines.iter().map(|line| line.to_string()).collect()).unwrap(), install_sshd: false }
}

// ---- service

#[tokio::test]
async fn a_running_workload_gets_the_whole_list_and_the_report_says_where_sshd_is() {
    let (engine, service) = machine();
    engine.set_sshd(Sshd::Running);
    let done = service.apply_ssh_keys("w-1", keys(&[KEY, "ssh-rsa AAAA bob"])).await.ok().unwrap();
    assert_eq!((done.applied, done.sshd), (2, Sshd::Running));
    assert_eq!(engine.written_ssh_keys("w-1").unwrap(), format!("{KEY}\nssh-rsa AAAA bob\n").into_bytes());
    let emptied = service.apply_ssh_keys("w-1", keys(&[])).await.ok().unwrap();
    assert_eq!(emptied.applied, 0);
    assert_eq!(engine.written_ssh_keys("w-1").unwrap(), Vec::<u8>::new(), "the list is replaced, an empty list leaves an empty file");
}

#[tokio::test]
async fn an_unknown_workload_is_not_found() {
    let (_, service) = machine();
    assert!(matches!(service.apply_ssh_keys("w-none", keys(&[KEY])).await, Err(Failure::NotFound)));
}

#[tokio::test]
async fn a_stopped_workload_is_refused_with_not_running_and_nothing_is_written() {
    let (engine, service) = machine();
    service.set_running("stop-1", "w-1", false).await.ok().unwrap();
    let Err(Failure::Refused(refusal)) = service.apply_ssh_keys("w-1", keys(&[KEY])).await else { panic!("expected a refusal") };
    assert_eq!(refusal.code, "not_running");
    assert!(engine.written_ssh_keys("w-1").is_none());
}

// ---- route

pub(crate) async fn send(service: &Arc<Service>, method: &str, path: &str, body: &str, token: &str) -> (StatusCode, Value) {
    let app = router(App::new(service.clone(), TOKEN.into(), 10));
    let mut request = Request::builder().method(method).uri(path).header("authorization", format!("Bearer {token}")).body(Body::from(body.to_string())).unwrap();
    request.extensions_mut().insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))));
    let response = app.oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

pub(crate) fn body_of(lines: &[&str]) -> String {
    json!({ "keys": lines }).to_string()
}

#[tokio::test]
async fn the_route_answers_200_with_the_count_and_the_sshd_word() {
    let (engine, service) = machine();
    engine.set_sshd(Sshd::Installed);
    let (status, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY]), TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, json!({"applied": 1, "sshd": "installed"})));
    let (status, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[]), TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, json!({"applied": 0, "sshd": "installed"})));
}

#[tokio::test]
async fn the_route_answers_400_for_a_bad_body_and_names_the_position_not_the_key() {
    let (engine, service) = machine();
    let injected = format!("command=\"echo hi\" {KEY}");
    let too_many = vec![KEY; ssh_keys::MAX_KEYS + 1];
    for bad in [body_of(&[KEY, &injected]), body_of(&too_many), "{}".into(), "nope".into(), json!({"keys": [KEY], "other": 1}).to_string(), json!({"keys": [KEY, "a\nb"]}).to_string()] {
        let (status, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &bad, TOKEN).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{bad}");
        assert_eq!(answer["error"]["code"], "invalid_input");
        assert!(!answer.to_string().contains("AAAAC3"), "the key must not be echoed: {answer}");
    }
    let (_, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY, &injected]), TOKEN).await;
    assert!(answer["error"]["message"].as_str().unwrap().contains("keys/1"));
    assert!(engine.written_ssh_keys("w-1").is_none(), "a bad list changes nothing");
}

#[tokio::test]
async fn the_route_answers_404_for_an_unknown_or_malformed_id() {
    let (_, service) = machine();
    for path in ["/v1/workloads/w-none/ssh-keys", "/v1/workloads/BAD_ID/ssh-keys"] {
        let (status, answer) = send(&service, "PUT", path, &body_of(&[KEY]), TOKEN).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{path}");
        assert_eq!(answer["error"]["code"], "not_found");
    }
}

#[tokio::test]
async fn the_route_answers_409_not_running_for_a_stopped_vm() {
    let (_, service) = machine();
    service.set_running("stop-1", "w-1", false).await.ok().unwrap();
    let (status, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY]), TOKEN).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(answer["error"]["code"], "not_running");
}

#[tokio::test]
async fn the_route_needs_the_bearer_token_and_the_put_method() {
    let (_, service) = machine();
    let (status, _) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY]), "wrong").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let (status, _) = send(&service, "POST", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY]), TOKEN).await;
    assert_eq!(status, StatusCode::METHOD_NOT_ALLOWED);
}

// ---- the Incus engine's exact call

/// Answers `incus list` with one instance in the given state and records every call with its standard input.
struct Recording {
    status: &'static str,
    report: String,
    calls: Mutex<Vec<(Vec<String>, Vec<u8>)>>,
}

impl Recording {
    fn new(status: &'static str, report: &str) -> Arc<Self> {
        Arc::new(Recording { status, report: report.into(), calls: Mutex::new(Vec::new()) })
    }

    fn inputs(&self) -> Vec<(Vec<String>, Vec<u8>)> {
        self.calls.lock().unwrap().iter().filter(|(arguments, _)| arguments[0] == "exec").cloned().collect()
    }
}

impl Runner for Recording {
    fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push((arguments.to_vec(), Vec::new()));
        let instance = json!([{"name": "ms-w-1", "status": self.status, "config": {"user.metaservice.id": "w-1", "user.metaservice.name": "box", "user.metaservice.kind": "vm",
            "user.metaservice.cpu": "1", "user.metaservice.ram_mb": "512", "user.metaservice.disk_gb": "1"}, "state": null}]);
        Ok(instance.to_string())
    }

    fn run_with_input(&self, arguments: &[String], input: &[u8], _timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push((arguments.to_vec(), input.to_vec()));
        Ok(self.report.clone())
    }
}

fn incus_over(runner: Arc<Recording>) -> Arc<Service> {
    let capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY, sandbox: false };
    service_over(Arc::new(IncusEngine::new(runner, capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1)))
}

#[tokio::test]
async fn incus_gets_the_fixed_exec_with_the_keys_on_standard_input_only() {
    let runner = Recording::new("Running", "sshd=installed\n");
    let service = incus_over(runner.clone());
    let done = service.apply_ssh_keys("w-1", keys(&[KEY, "ssh-rsa AAAA bob"])).await.ok().unwrap();
    assert_eq!((done.applied, done.sshd), (2, Sshd::Installed));
    let runs = runner.inputs();
    assert_eq!(runs.len(), 1);
    assert_eq!(runs[0].0, ssh_keys::incus_call("ms-w-1"), "the atomic-write script constant is what runs");
    assert_eq!(runs[0].1, format!("{KEY}\nssh-rsa AAAA bob\n").into_bytes());
    for (arguments, _) in runner.calls.lock().unwrap().iter() {
        assert!(!arguments.iter().any(|part| part.contains("AAAA") || part.contains("alice")), "no key text in any command line: {arguments:?}");
    }
}

#[tokio::test]
async fn incus_is_not_asked_to_exec_in_a_stopped_vm() {
    let runner = Recording::new("Stopped", "sshd=running\n");
    let Err(Failure::Refused(refusal)) = incus_over(runner.clone()).apply_ssh_keys("w-1", keys(&[KEY])).await else { panic!("expected a refusal") };
    assert_eq!(refusal.code, "not_running");
    assert!(runner.inputs().is_empty());
}

#[tokio::test]
async fn a_vm_that_does_not_report_is_an_engine_failure_that_says_nothing_inside() {
    let runner = Recording::new("Running", "no report here\n");
    let service = incus_over(runner);
    assert!(matches!(service.apply_ssh_keys("w-1", keys(&[KEY])).await, Err(Failure::Engine(_))));
    let (status, answer) = send(&service, "PUT", "/v1/workloads/w-1/ssh-keys", &body_of(&[KEY]), TOKEN).await;
    assert_eq!((status, answer["error"]["code"].as_str()), (StatusCode::INTERNAL_SERVER_ERROR, Some("internal")));
}

// ---- the real process runner

/// A folder holding one fake `incus` made of the given shell lines.
fn fake_incus(lines: &str) -> (ProcessRunner, PathBuf) {
    use std::os::unix::fs::PermissionsExt;
    let folder = std::env::temp_dir().join(format!("ms-fake-ssh-{}", rand::random::<u64>()));
    std::fs::create_dir_all(&folder).unwrap();
    let program = folder.join("incus");
    std::fs::write(&program, format!("#!/bin/sh\n{lines}\n")).unwrap();
    std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o755)).unwrap();
    (ProcessRunner { path: program.display().to_string() }, folder)
}

fn call() -> Vec<String> {
    ssh_keys::incus_call("ms-w-1")
}

#[test]
fn the_process_runner_sends_the_input_on_standard_input_and_not_in_the_arguments() {
    let (runner, folder) = fake_incus("cat > \"$(dirname \"$0\")/stdin.txt\"\necho \"$@\" > \"$(dirname \"$0\")/argv.txt\"\necho sshd=running");
    let output = runner.run_with_input(&call(), format!("{KEY}\n").as_bytes(), TIME_LIMIT).unwrap();
    assert_eq!(output.trim(), "sshd=running");
    assert_eq!(std::fs::read_to_string(folder.join("stdin.txt")).unwrap(), format!("{KEY}\n"));
    assert!(!std::fs::read_to_string(folder.join("argv.txt")).unwrap().contains("AAAAC3"));
}

#[test]
fn a_call_without_input_has_an_empty_standard_input() {
    let (runner, _) = fake_incus("cat; echo done");
    assert_eq!(runner.run(&call(), TIME_LIMIT).unwrap().trim(), "done");
}

#[test]
fn a_program_that_never_reads_its_input_does_not_hang_the_helper() {
    let (runner, _) = fake_incus("echo sshd=missing");
    let big = vec![b'a'; 4 * 1024 * 1024];
    assert_eq!(runner.run_with_input(&call(), &big, TIME_LIMIT).unwrap().trim(), "sshd=missing");
}

#[test]
fn a_call_that_runs_too_long_is_stopped_with_an_error() {
    let (runner, _) = fake_incus("sleep 30");
    let error = runner.run_with_input(&call(), b"x\n", Duration::from_millis(300)).unwrap_err();
    assert!(matches!(error, EngineError::Failed(ref text) if text.contains("took too long")), "{error:?}");
}

#[test]
fn a_flood_of_output_is_capped_and_ends_in_an_error_not_in_memory() {
    let (runner, _) = fake_incus("head -c 20000000 /dev/zero | tr '\\0' 'a'");
    assert!(runner.run_with_input(&call(), b"x\n", TIME_LIMIT).is_err());
}

#[test]
fn a_failing_program_reports_its_exit_code_and_the_tail_of_its_errors() {
    let (runner, _) = fake_incus("echo 'mv: cannot move' >&2; exit 3");
    let error = runner.run_with_input(&call(), b"x\n", TIME_LIMIT).unwrap_err();
    assert!(matches!(error, EngineError::Failed(ref text) if text.contains("exited with 3") && text.contains("cannot move")), "{error:?}");
}
