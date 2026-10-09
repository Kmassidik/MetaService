//! The one-time host setup an operator runs as root: `metaservice-agent setup` shows the plan, `--yes` applies it.
//! A fixed list of steps per distro family, each safe to repeat. The running Agent never does any of this itself.
use crate::preflight::managed_bridge;
use std::process::{Command, Stdio};

const INCUS_GROUP: &str = "incus-admin";
const SUBID_LINE: &str = "root:1000000:1000000000";
const TRUSTED_ZONE: &str = "trusted";
const NETWORK_LIST: [&str; 4] = ["network", "list", "--format", "csv"];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Family {
    RedHat,
    Debian,
}

/// From /etc/os-release: ID and ID_LIKE name the family.
pub fn family_from_os_release(text: &str) -> Option<Family> {
    let words: Vec<String> = text.lines().filter(|l| l.starts_with("ID=") || l.starts_with("ID_LIKE=")).flat_map(|l| {
        l.split_once('=').map(|(_, v)| v.trim_matches('"').split_whitespace().map(str::to_string).collect::<Vec<_>>()).unwrap_or_default()
    }).collect();
    let has = |names: &[&str]| words.iter().any(|w| names.contains(&w.as_str()));
    if has(&["fedora", "rhel", "centos", "rocky", "almalinux"]) { return Some(Family::RedHat); }
    has(&["debian", "ubuntu"]).then_some(Family::Debian)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Step {
    Run { why: &'static str, program: &'static str, args: Vec<String> },
    EnsureLine { why: &'static str, path: &'static str, line: &'static str },
    InitIncus,
    TrustBridge,
}

impl Step {
    pub fn describe(&self) -> String {
        match self {
            Step::Run { why, program, args } => format!("{why}: {program} {}", args.join(" ")),
            Step::EnsureLine { why, path, line } => format!("{why}: make sure {path} contains \"{line}\""),
            Step::InitIncus => "Create Incus's default storage and network if it has none: incus admin init --minimal".into(),
            Step::TrustBridge => "If firewalld is running, put Incus's VM bridge in the trusted zone so VMs get an IPv4 address: firewall-cmd --permanent --zone=trusted --add-interface=<bridge>, then --reload".into(),
        }
    }
}

fn run(why: &'static str, program: &'static str, args: &[&str]) -> Step {
    Step::Run { why, program, args: args.iter().map(|a| a.to_string()).collect() }
}

/// A login name that is safe to hand to usermod.
fn valid_user(name: &str) -> bool {
    let mut chars = name.chars();
    chars.next().is_some_and(|c| c.is_ascii_lowercase() || c == '_') && name.len() <= 32 && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, '_' | '-'))
}

pub fn plan(family: Family, user: &str) -> Result<Vec<Step>, String> {
    if !valid_user(user) {
        return Err(format!("{user:?} is not a valid user name"));
    }
    let install = match family {
        Family::RedHat => run("Install Incus", "dnf", &["install", "-y", "incus", "incus-client"]),
        Family::Debian => run("Install Incus", "apt-get", &["install", "-y", "incus"]),
    };
    Ok(vec![
        install,
        Step::EnsureLine { why: "Let Incus map user ids for unprivileged instances", path: "/etc/subuid", line: SUBID_LINE },
        Step::EnsureLine { why: "Let Incus map group ids for unprivileged instances", path: "/etc/subgid", line: SUBID_LINE },
        run("Start Incus now and at every boot", "systemctl", &["enable", "--now", "incus.socket", "incus.service"]),
        Step::Run { why: "Let the Agent's user manage Incus", program: "usermod", args: vec!["-aG".into(), INCUS_GROUP.into(), user.into()] },
        Step::InitIncus,
        Step::TrustBridge,
    ])
}

/// What the steps run on. The real one touches the machine; tests use a scripted one.
pub trait Host {
    fn run(&self, program: &str, args: &[String]) -> Result<String, String>;
    /// Adds the line to the file unless the file already has an entry for root. True when it changed the file.
    fn ensure_line(&self, path: &str, line: &str) -> Result<bool, String>;
}

pub struct RealHost;

impl Host for RealHost {
    fn run(&self, program: &str, args: &[String]) -> Result<String, String> {
        let output = Command::new(program).args(args).stdin(Stdio::null()).output().map_err(|e| format!("{program}: {e}"))?;
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.success() { return Ok(text); }
        let errors = String::from_utf8_lossy(&output.stderr);
        Err(format!("{program} exited with {}: {}", output.status.code().unwrap_or(-1), errors.chars().rev().take(300).collect::<String>().chars().rev().collect::<String>()))
    }

    fn ensure_line(&self, path: &str, line: &str) -> Result<bool, String> {
        let existing = std::fs::read_to_string(path).unwrap_or_default();
        if existing.lines().any(|l| l.starts_with("root:")) { return Ok(false); }
        let separator = if existing.is_empty() || existing.ends_with('\n') { "" } else { "\n" };
        std::fs::write(path, format!("{existing}{separator}{line}\n")).map_err(|e| format!("{path}: {e}"))?;
        Ok(true)
    }
}

/// Runs the steps in order and reports each outcome through `say`. Stops at the first failure.
pub fn execute(steps: &[Step], host: &dyn Host, say: &mut dyn FnMut(String)) -> Result<(), String> {
    for step in steps {
        say(format!("-> {}", step.describe()));
        apply(step, host, say).map_err(|error| format!("stopped: {error}"))?;
    }
    Ok(())
}

fn apply(step: &Step, host: &dyn Host, say: &mut dyn FnMut(String)) -> Result<(), String> {
    match step {
        Step::Run { program, args, .. } => host.run(program, args).map(drop),
        Step::EnsureLine { path, line, .. } => host.ensure_line(path, line).map(|changed| say(if changed { "   added".into() } else { "   already there".into() })),
        Step::InitIncus => init_incus(host, say),
        Step::TrustBridge => trust_bridge(host, say),
    }
}

fn bridge_of(host: &dyn Host) -> Result<Option<String>, String> {
    let args: Vec<String> = NETWORK_LIST.iter().map(|a| a.to_string()).collect();
    host.run("incus", &args).map(|csv| managed_bridge(&csv))
}

fn init_incus(host: &dyn Host, say: &mut dyn FnMut(String)) -> Result<(), String> {
    if bridge_of(host)?.is_some() {
        say("   already set up".into());
        return Ok(());
    }
    host.run("incus", &["admin".into(), "init".into(), "--minimal".into()]).map(drop)
}

fn trust_bridge(host: &dyn Host, say: &mut dyn FnMut(String)) -> Result<(), String> {
    if host.run("firewall-cmd", &["--state".into()]).as_deref() != Ok("running") {
        say("   no running firewalld, nothing to change".into());
        return Ok(());
    }
    let Some(bridge) = bridge_of(host)? else { return Err("Incus has no managed bridge to trust".into()) };
    let zone = host.run("firewall-cmd", &[format!("--get-zone-of-interface={bridge}")]).unwrap_or_default();
    if zone == TRUSTED_ZONE {
        say(format!("   {bridge} is already trusted"));
        return Ok(());
    }
    host.run("firewall-cmd", &["--permanent".into(), format!("--zone={TRUSTED_ZONE}"), format!("--add-interface={bridge}")])?;
    host.run("firewall-cmd", &["--reload".into()]).map(drop)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    #[derive(Default)]
    struct Scripted {
        answers: HashMap<String, Result<String, String>>,
        calls: RefCell<Vec<String>>,
        lines: RefCell<Vec<String>>,
    }

    impl Scripted {
        fn answer(mut self, call: &str, result: Result<&str, &str>) -> Self {
            self.answers.insert(call.into(), result.map(String::from).map_err(String::from));
            self
        }
    }

    impl Host for Scripted {
        fn run(&self, program: &str, args: &[String]) -> Result<String, String> {
            let call = format!("{program} {}", args.join(" "));
            self.calls.borrow_mut().push(call.clone());
            self.answers.get(&call).cloned().unwrap_or(Ok(String::new()))
        }

        fn ensure_line(&self, path: &str, line: &str) -> Result<bool, String> {
            self.lines.borrow_mut().push(format!("{path}:{line}"));
            Ok(true)
        }
    }

    const BRIDGE: &str = "incus network list --format csv";
    const NETWORKS: &str = "incusbr0,bridge,YES,10.0.0.1/24,,,1,CREATED";

    fn run_all(host: &Scripted) -> (Result<(), String>, Vec<String>) {
        let mut said = Vec::new();
        let result = execute(&plan(Family::RedHat, "kurnia").unwrap(), host, &mut |line| said.push(line));
        (result, said)
    }

    #[test]
    fn the_distro_family_comes_from_os_release() {
        assert_eq!(family_from_os_release("NAME=Fedora\nID=fedora\n"), Some(Family::RedHat));
        assert_eq!(family_from_os_release("ID=rocky\nID_LIKE=\"rhel centos fedora\"\n"), Some(Family::RedHat));
        assert_eq!(family_from_os_release("ID=ubuntu\nID_LIKE=debian\n"), Some(Family::Debian));
        assert_eq!(family_from_os_release("ID=linuxmint\nID_LIKE=\"ubuntu debian\"\n"), Some(Family::Debian));
        assert_eq!(family_from_os_release("ID=nixos\n"), None);
    }

    #[test]
    fn the_plan_installs_enables_adds_the_user_and_trusts_the_bridge() {
        let text: Vec<String> = plan(Family::RedHat, "kurnia").unwrap().iter().map(Step::describe).collect();
        assert!(text[0].contains("dnf install -y incus incus-client"));
        assert!(text.iter().any(|t| t.contains("usermod -aG incus-admin kurnia")));
        assert!(text.iter().any(|t| t.contains("/etc/subuid")) && text.iter().any(|t| t.contains("/etc/subgid")));
        assert!(text.last().unwrap().contains("trusted zone"));
        assert!(plan(Family::Debian, "kurnia").unwrap()[0].describe().contains("apt-get install -y incus"));
    }

    #[test]
    fn only_plain_user_names_are_accepted() {
        for bad in ["", "Kurnia", "a b", "x;rm -rf /", "-n", "1abc", "a$(id)", &"a".repeat(33)] {
            assert!(plan(Family::RedHat, bad).is_err(), "{bad:?}");
        }
        for good in ["kurnia", "_svc", "dev-1", "a_b"] {
            assert!(plan(Family::RedHat, good).is_ok(), "{good:?}");
        }
    }

    #[test]
    fn a_fresh_host_gets_every_step_in_order() {
        let host = Scripted::default().answer("firewall-cmd --state", Ok("running")).answer("firewall-cmd --get-zone-of-interface=incusbr0", Ok("no zone"));
        let host = host.answer(BRIDGE, Ok("")).answer("incus admin init --minimal", Ok(""));
        let (result, _) = run_all(&host);
        assert!(result.is_err(), "no bridge appears after init in this script, so trusting it must fail loudly: {result:?}");
        let calls = host.calls.borrow().join("|");
        assert!(calls.find("dnf install").unwrap() < calls.find("systemctl enable").unwrap() && calls.find("systemctl enable").unwrap() < calls.find("usermod").unwrap());
        assert!(calls.contains("incus admin init --minimal"));
    }

    #[test]
    fn a_ready_host_is_left_alone_and_the_run_is_repeatable() {
        let host = Scripted::default().answer(BRIDGE, Ok(NETWORKS)).answer("firewall-cmd --state", Ok("running")).answer("firewall-cmd --get-zone-of-interface=incusbr0", Ok("trusted"));
        let (result, said) = run_all(&host);
        assert_eq!(result, Ok(()));
        let calls = host.calls.borrow().join("|");
        assert!(!calls.contains("admin init") && !calls.contains("--add-interface") && !calls.contains("--reload"), "{calls}");
        assert!(said.iter().any(|s| s.contains("already set up")) && said.iter().any(|s| s.contains("already trusted")));
    }

    #[test]
    fn an_untrusted_bridge_is_trusted_then_the_firewall_reloads() {
        let host = Scripted::default().answer(BRIDGE, Ok(NETWORKS)).answer("firewall-cmd --state", Ok("running")).answer("firewall-cmd --get-zone-of-interface=incusbr0", Ok("no zone"));
        assert_eq!(run_all(&host).0, Ok(()));
        let calls = host.calls.borrow().clone();
        let add = calls.iter().position(|c| c == "firewall-cmd --permanent --zone=trusted --add-interface=incusbr0").expect("the bridge is added");
        assert_eq!(calls[add + 1], "firewall-cmd --reload");
    }

    #[test]
    fn without_a_running_firewall_nothing_is_changed_and_a_failure_stops_the_run() {
        let host = Scripted::default().answer(BRIDGE, Ok(NETWORKS)).answer("firewall-cmd --state", Err("not running"));
        assert_eq!(run_all(&host).0, Ok(()));
        assert!(!host.calls.borrow().iter().any(|c| c.contains("--add-interface")));
        let broken = Scripted::default().answer("dnf install -y incus incus-client", Err("no network"));
        let (result, _) = run_all(&broken);
        assert_eq!(result, Err("stopped: no network".into()));
        assert_eq!(broken.calls.borrow().len(), 1, "nothing runs after a failure");
    }
}
