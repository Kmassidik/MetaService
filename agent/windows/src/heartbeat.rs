//! Tells the Root, every few seconds, what this machine is. It speaks up at once after a change.
//! Decoupled from the VM service: the Windows helper has no workloads, so the body is a closure
//! that assembles the facts value (the caller owns how facts are read).
use serde_json::Value;
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

const SLOW_SECONDS: u64 = 60;

pub struct Heartbeat {
    root: String,
    token: String,
    port: u16,
    seconds: u64,
    wake: (Mutex<bool>, Condvar),
    body: Box<dyn Fn() -> Option<Value> + Send + Sync>,
}

impl Heartbeat {
    /// `body` returns the heartbeat payload, or None when the facts could not be read this time.
    pub fn new(root: String, token: String, port: u16, seconds: u64, body: impl Fn() -> Option<Value> + Send + Sync + 'static) -> Arc<Heartbeat> {
        Arc::new(Heartbeat { root, token, port, seconds, wake: (Mutex::new(false), Condvar::new()), body: Box::new(body) })
    }

    /// Ask for a heartbeat now instead of at the next interval.
    pub fn beat_soon(&self) {
        *self.wake.0.lock().unwrap() = true;
        self.wake.1.notify_all();
    }

    /// Runs on its own thread, forever. A failure is logged once and retried more slowly.
    pub fn spawn(self: &Arc<Self>) {
        let this = self.clone();
        std::thread::spawn(move || {
            let mut failing = false;
            loop {
                let ok = this.beat();
                if !ok && !failing { eprintln!("metaservice-agent: cannot reach the Root; will keep trying"); }
                if ok && failing { eprintln!("metaservice-agent: the Root is reachable again"); }
                failing = !ok;
                this.rest(if ok { this.seconds } else { SLOW_SECONDS });
            }
        });
    }

    fn rest(&self, seconds: u64) {
        let (flag, condvar) = &self.wake;
        let guard = flag.lock().unwrap();
        let (mut guard, _) = condvar.wait_timeout_while(guard, Duration::from_secs(seconds), |soon| !*soon).unwrap();
        *guard = false;
    }

    fn beat(&self) -> bool {
        let Some(body) = (self.body)() else { return false };
        let mut payload = body;
        payload["agent_port"] = self.port.into();
        ureq::post(&format!("{}/v1/agents/heartbeat", self.root)).timeout(Duration::from_secs(15))
            .set("Authorization", &format!("Bearer {}", self.token))
            .set("Content-Type", "application/json").send_string(&payload.to_string()).is_ok_and(|r| r.status() == 204)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_body_of_none_is_a_failed_beat() {
        let beat = Heartbeat::new("http://127.0.0.1:1".into(), "t".into(), 9101, 60, || None);
        assert!(!beat.beat());
    }
}
