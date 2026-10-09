//! Is this machine ready to run VMs? The Agent checks the things that fail quietly on a real host and reports each one with its fix.
//! It only looks. Changing the host (packages, groups, firewall) is the operator's one-time `setup` command, never the running Agent.
use crate::incus::Runner;
use crate::models::Problem;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const QUICK: Duration = Duration::from_secs(10);
const PROBE_SECONDS: u64 = 5;
const SETUP_FIX: &str = "As root, run: metaservice-agent setup --yes (it shows what it will change first), then restart the Agent.";
const TRUSTED_ZONE: &str = "trusted";
const NO_ZONE: &str = "no zone";

/// What a host program answered: whether it succeeded, and what it printed on each stream (trimmed).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProbeOutput {
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
}

/// Reads one fact from the host program-by-program. Never a shell, never a value from a request.
pub trait HostProbe: Send + Sync {
    /// None only when the program could not be run at all (missing, or it took too long).
    fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput>;
}

pub struct SystemProbe;

impl HostProbe for SystemProbe {
    fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput> {
        let mut child = Command::new(program).args(arguments).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().ok()?;
        let deadline = Instant::now() + Duration::from_secs(PROBE_SECONDS);
        let status = loop {
            if let Some(status) = child.try_wait().ok()? { break status; }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            std::thread::sleep(Duration::from_millis(20));
        };
        let read = |stream: Option<&mut dyn std::io::Read>| {
            let mut text = String::new();
            if let Some(stream) = stream { let _ = stream.read_to_string(&mut text); }
            text.trim().to_string()
        };
        let stdout = read(child.stdout.as_mut().map(|s| s as &mut dyn std::io::Read));
        let stderr = read(child.stderr.as_mut().map(|s| s as &mut dyn std::io::Read));
        Some(ProbeOutput { success: status.success(), stdout, stderr })
    }
}

/// Used where no host checks apply (tests, and engines that need none).
pub struct NoHostChecks;

impl HostProbe for NoHostChecks {
    fn run(&self, _program: &str, _arguments: &[&str]) -> Option<ProbeOutput> {
        None
    }
}

pub fn incus_host(incus: &dyn Runner, probe: &dyn HostProbe) -> Vec<Problem> {
    let args = ["network", "list", "--format", "csv"].map(String::from);
    let Ok(networks) = incus.run(&args, QUICK) else { return vec![incus_unreachable()] };
    managed_bridge(&networks).and_then(|bridge| firewall_problem(&bridge, probe)).into_iter().collect()
}

fn incus_unreachable() -> Problem {
    Problem {
        code: "incus_unreachable".into(),
        message: "The Agent cannot use Incus. It may be missing, stopped, or this user is not in the incus-admin group.".into(),
        fix: SETUP_FIX.into(),
    }
}

/// The first Incus-managed bridge, by the csv of `incus network list` (name,type,managed,...). Names that are not plain interface names are ignored.
pub fn managed_bridge(csv: &str) -> Option<String> {
    csv.lines().map(|line| line.split(',').collect::<Vec<_>>()).find_map(|fields| match fields[..] {
        [name, "bridge", "YES", ..] if is_interface_name(name) => Some(name.to_string()),
        _ => None,
    })
}

fn is_interface_name(name: &str) -> bool {
    (1..=15).contains(&name.len()) && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))
}

/// With firewalld running, the VM bridge must be in the trusted zone, or the host drops the VMs' DHCP requests and they never get an IPv4 address.
/// Only `--get-zone-of-interface` is used because it answers without root (`--state` needs polkit). It prints the zone name and succeeds, or
/// prints "no zone" on stderr and fails. Any other failure (firewalld stopped, no permission, no firewall-cmd) is not evidence of a problem.
fn firewall_problem(bridge: &str, probe: &dyn HostProbe) -> Option<Problem> {
    let answer = probe.run("firewall-cmd", &[&format!("--get-zone-of-interface={bridge}")])?;
    let blocked = if answer.success { !answer.stdout.is_empty() && answer.stdout != TRUSTED_ZONE } else { answer.stderr == NO_ZONE };
    blocked.then(|| Problem {
        code: "bridge_blocked_by_firewall".into(),
        message: format!("VMs cannot get an IPv4 address: the bridge {bridge} is not in firewalld's trusted zone, so the host drops their DHCP requests."),
        fix: SETUP_FIX.into(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::EngineError;
    use std::collections::HashMap;

    struct FakeIncus(Result<String, ()>);

    impl Runner for FakeIncus {
        fn run(&self, _arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
            self.0.clone().map_err(|_| EngineError::Failed("incus broke".into()))
        }
    }

    /// Scripted answers keyed by "program args": (success, stdout, stderr).
    struct FakeHost(HashMap<String, ProbeOutput>);

    impl FakeHost {
        fn with(items: &[(&str, bool, &str, &str)]) -> Self {
            FakeHost(items.iter().map(|(k, ok, out, err)| (k.to_string(), ProbeOutput { success: *ok, stdout: out.to_string(), stderr: err.to_string() })).collect())
        }
    }

    impl HostProbe for FakeHost {
        fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput> {
            self.0.get(&format!("{program} {}", arguments.join(" "))).cloned()
        }
    }

    const ZONE: &str = "firewall-cmd --get-zone-of-interface=incusbr0";

    const NETWORKS: &str = "docker0,bridge,NO,,,,0,\nenp44s0,physical,NO,,,,0,\nincusbr0,bridge,YES,10.239.152.1/24,fd42::1/64,,1,CREATED\n";

    fn check(networks: Result<&str, ()>, host: &[(&str, bool, &str, &str)]) -> Vec<Problem> {
        incus_host(&FakeIncus(networks.map(String::from)), &FakeHost::with(host))
    }

    #[test]
    fn a_bridge_outside_the_trusted_zone_is_reported_with_the_fix() {
        let in_wrong_zone = [(ZONE, true, "FedoraWorkstation", ""), (ZONE, true, "public", "")];
        let in_no_zone = [(ZONE, false, "", "no zone")];
        for answer in in_wrong_zone.iter().chain(&in_no_zone) {
            let found = check(Ok(NETWORKS), &[*answer]);
            assert_eq!(found.len(), 1, "{answer:?}");
            assert_eq!(found[0].code, "bridge_blocked_by_firewall");
            assert!(found[0].message.contains("incusbr0") && found[0].fix.contains("setup --yes"));
        }
    }

    #[test]
    fn a_trusted_bridge_or_no_usable_firewall_answer_is_fine() {
        assert!(check(Ok(NETWORKS), &[(ZONE, true, "trusted", "")]).is_empty());
        assert!(check(Ok(NETWORKS), &[(ZONE, false, "", "FirewallD is not running")]).is_empty(), "firewalld stopped");
        assert!(check(Ok(NETWORKS), &[(ZONE, false, "", "Authorization failed.")]).is_empty(), "no permission to ask");
        assert!(check(Ok(NETWORKS), &[]).is_empty(), "no firewall-cmd at all");
    }

    #[test]
    fn the_real_laptop_answer_is_a_problem() {
        // Seen on Fedora 44: stdout empty, stderr "no zone", exit code 2.
        assert_eq!(check(Ok(NETWORKS), &[(ZONE, false, "", "no zone")]).len(), 1);
    }

    #[test]
    fn unreachable_incus_is_one_problem_and_the_firewall_is_not_asked() {
        let found = check(Err(()), &[(ZONE, false, "", "no zone")]);
        assert_eq!(found.iter().map(|p| p.code.as_str()).collect::<Vec<_>>(), ["incus_unreachable"]);
    }

    #[test]
    fn only_a_managed_bridge_with_a_plain_name_counts() {
        assert_eq!(managed_bridge("docker0,bridge,NO,,\nenp1,physical,NO,,"), None);
        assert_eq!(managed_bridge("br0,bridge,YES,,"), Some("br0".into()));
        for hostile in ["a b,bridge,YES", "x;rm,bridge,YES", "averyveryverylongname,bridge,YES", ",bridge,YES"] {
            assert_eq!(managed_bridge(hostile), None, "{hostile}");
        }
    }
}
