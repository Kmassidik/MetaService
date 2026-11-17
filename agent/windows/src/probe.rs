//! Reads host facts program-by-program (Windows port of the Linux preflight's probe half).
//! The Windows helper v1 has no VM engine, so there is no engine preflight; only the probe
//! plumbing that stats and the GPU reader share with the other helpers.

/// What a host program answered: whether it succeeded, and what it printed on each stream (trimmed).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProbeOutput {
    pub success: bool,
    pub stdout: String,
    pub stderr: String,
}

use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// How long one host program may run before it counts as missing.
const PROBE_SECONDS: u64 = 5;

/// Reads one fact from the host program-by-program. Never a shell, never a value from a request.
pub trait HostProbe: Send + Sync {
    /// None only when the program could not be run at all (missing, or it took too long).
    fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput>;
}

/// Runs real programs. `searching` swaps the folders the programs are looked for in (tests use it to put fake programs on a fake PATH).
#[derive(Default)]
pub struct SystemProbe {
    search_path: Option<std::ffi::OsString>,
}

impl SystemProbe {
    #[cfg(test)]
    pub fn searching(path: impl Into<std::ffi::OsString>) -> Self {
        SystemProbe { search_path: Some(path.into()) }
    }
}

impl HostProbe for SystemProbe {
    fn run(&self, program: &str, arguments: &[&str]) -> Option<ProbeOutput> {
        let mut command = Command::new(program);
        command.args(arguments).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
        if let Some(path) = &self.search_path {
            command.env("PATH", path);
        }
        let mut child = command.spawn().ok()?;
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


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_probe_runs_a_real_program() {
        let probe = SystemProbe::default();
        let answer = probe.run(if cfg!(windows) { "cmd" } else { "echo" }, &[if cfg!(windows) { "/c echo hi" } else { "hi" }]);
        assert!(answer.is_some_and(|a| a.success && a.stdout.contains("hi")));
    }

    #[test]
    fn a_missing_program_is_none_not_an_error() {
        let probe = SystemProbe::searching("/nonexistent-folder");
        assert!(probe.run("definitely-not-here", &[]).is_none());
    }
}
