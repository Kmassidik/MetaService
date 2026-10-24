//! The helper's side of the runner socket: one connection per request, one line out, one line back.
//!
//! The helper never retries a request by itself. Every request carries the sandbox's id, so a retry from the caller is safe where it matters, and a
//! runner that cannot be reached is reported as "cannot run sandboxes" rather than as a half-done create.
use super::protocol::{read_line, Reply, Request};
use super::Runner;
use std::io::{BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

/// How long one request may take. A step that hangs is worse than a step that fails: the helper has a sandbox to answer for.
const TIMEOUT: Duration = Duration::from_secs(10);

/// The runner, reached over its unix socket.
#[derive(Clone, Debug)]
pub struct RunnerClient {
    socket: PathBuf,
}

impl RunnerClient {
    pub fn new(socket: PathBuf) -> RunnerClient {
        RunnerClient { socket }
    }

    /// One request, one answer. A refusal from the runner is its reason, in plain words, for the helper's log.
    fn ask(&self, request: &Request) -> Result<Reply, String> {
        let mut stream = UnixStream::connect(&self.socket).map_err(|e| format!("the sandbox runner is not reachable at {}: {e}", self.socket.display()))?;
        stream.set_read_timeout(Some(TIMEOUT)).map_err(|e| format!("the sandbox runner socket cannot be timed: {e}"))?;
        stream.set_write_timeout(Some(TIMEOUT)).map_err(|e| format!("the sandbox runner socket cannot be timed: {e}"))?;
        stream.write_all(format!("{}\n", request_line(request)).as_bytes()).map_err(|e| format!("cannot ask the sandbox runner: {e}"))?;
        stream.flush().map_err(|e| format!("cannot ask the sandbox runner: {e}"))?;
        let mut answers = BufReader::new(stream);
        let line = read_line(&mut answers)?.ok_or("the sandbox runner closed the connection without an answer")?;
        let reply = Reply::parse(&line)?;
        match reply {
            Reply::Failed { error } => Err(error),
            answer => Ok(answer),
        }
    }
}

impl Runner for RunnerClient {
    fn version(&self) -> Result<String, String> {
        match self.ask(&Request::Health)? {
            Reply::Health { version, .. } => Ok(version),
            other => Err(format!("the sandbox runner answered a health check with {}", other.to_line())),
        }
    }

    fn create_network(&self, id: &str, internet: bool) -> Result<(), String> {
        self.ask(&Request::CreateNetwork { id: id.to_string(), internet }).map(|_| ())
    }

    fn delete_network(&self, id: &str) -> Result<(), String> {
        self.ask(&Request::DeleteNetwork { id: id.to_string() }).map(|_| ())
    }

    fn start(&self, id: &str, vcpu: u32, ram_mb: u64) -> Result<(), String> {
        self.ask(&Request::Start { id: id.to_string(), vcpu, ram_mb }).map(|_| ())
    }

    fn stop(&self, id: &str) -> Result<(), String> {
        self.ask(&Request::Stop { id: id.to_string() }).map(|_| ())
    }

    fn pause(&self, id: &str) -> Result<(), String> {
        self.ask(&Request::Pause { id: id.to_string() }).map(|_| ())
    }

    fn resume(&self, id: &str) -> Result<(), String> {
        self.ask(&Request::Resume { id: id.to_string() }).map(|_| ())
    }

    fn snapshot(&self, id: &str) -> Result<(), String> {
        self.ask(&Request::Snapshot { id: id.to_string() }).map(|_| ())
    }
}

/// One request as the one line it travels as. It is written by `serde_json`, so no field is ever pasted into a string.
fn request_line(request: &Request) -> String {
    let value = match request {
        Request::Health => serde_json::json!({ "op": "health" }),
        Request::CreateNetwork { id, internet } => serde_json::json!({ "op": "create-network", "id": id, "internet": internet }),
        Request::DeleteNetwork { id } => serde_json::json!({ "op": "delete-network", "id": id }),
        Request::Start { id, vcpu, ram_mb } => serde_json::json!({ "op": "start", "id": id, "vcpu": vcpu, "ram_mb": ram_mb }),
        Request::Stop { id } => serde_json::json!({ "op": "stop", "id": id }),
        Request::Pause { id } => serde_json::json!({ "op": "pause", "id": id }),
        Request::Resume { id } => serde_json::json!({ "op": "resume", "id": id }),
        Request::Snapshot { id } => serde_json::json!({ "op": "snapshot", "id": id }),
    };
    value.to_string()
}


/// A runner that records what it was asked and answers as told: what the engine's tests run on. It runs nothing, so nothing it says is a sandbox.
#[cfg(test)]
pub struct FakeRunner {
    calls: std::sync::Mutex<Vec<String>>,
    /// The calls to refuse, and why: a prefix of the call, so one operation can fail while the rest work.
    failure: std::sync::Mutex<Option<(String, String)>>,
    version: String,
}

#[cfg(test)]
impl FakeRunner {
    pub fn new() -> std::sync::Arc<FakeRunner> {
        Self::answering("0.1.0")
    }

    pub fn answering(version: &str) -> std::sync::Arc<FakeRunner> {
        std::sync::Arc::new(FakeRunner { calls: std::sync::Mutex::new(Vec::new()), failure: std::sync::Mutex::new(None), version: version.into() })
    }

    /// A runner that refuses everything from now on, as one does when Firecracker is not installed on the machine.
    pub fn refusing(reason: &str) -> std::sync::Arc<FakeRunner> {
        let runner = FakeRunner::new();
        runner.refuse(reason);
        runner
    }

    pub fn refuse(&self, reason: &str) {
        self.refuse_when("", reason);
    }

    /// Refuse only the calls whose text starts with `calls`, as a runner whose Firecracker is missing does.
    pub fn refuse_when(&self, calls: &str, reason: &str) {
        *self.failure.lock().unwrap() = Some((calls.into(), reason.into()));
    }

    /// What it was asked, oldest first.
    pub fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }

    fn record(&self, call: String) -> Result<(), String> {
        self.calls.lock().unwrap().push(call.clone());
        match self.failure.lock().unwrap().as_ref() {
            Some((refused, reason)) if call.starts_with(refused.as_str()) => Err(reason.clone()),
            _ => Ok(()),
        }
    }
}

#[cfg(test)]
impl Runner for FakeRunner {
    fn version(&self) -> Result<String, String> {
        self.record("health".into())?;
        Ok(self.version.clone())
    }

    fn create_network(&self, id: &str, internet: bool) -> Result<(), String> {
        self.record(format!("create-network {id} {internet}"))
    }

    fn delete_network(&self, id: &str) -> Result<(), String> {
        self.record(format!("delete-network {id}"))
    }

    fn start(&self, id: &str, vcpu: u32, ram_mb: u64) -> Result<(), String> {
        self.record(format!("start {id} {vcpu} {ram_mb}"))
    }

    fn stop(&self, id: &str) -> Result<(), String> {
        self.record(format!("stop {id}"))
    }

    fn pause(&self, id: &str) -> Result<(), String> {
        self.record(format!("pause {id}"))
    }

    fn resume(&self, id: &str) -> Result<(), String> {
        self.record(format!("resume {id}"))
    }

    fn snapshot(&self, id: &str) -> Result<(), String> {
        self.record(format!("snapshot {id}"))
    }
}
