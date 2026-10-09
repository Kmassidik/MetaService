//! Tells the Root, every few seconds, what this machine is and what runs on it. It also speaks up at once after a change.
use crate::service::Service;
use serde_json::{json, Value};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

const SLOW_SECONDS: u64 = 60;

pub struct Heartbeat {
    root: String,
    token: String,
    port: u16,
    seconds: u64,
    wake: (Mutex<bool>, Condvar),
}

impl Heartbeat {
    pub fn new(root: String, token: String, port: u16, seconds: u64) -> Arc<Heartbeat> {
        Arc::new(Heartbeat { root, token, port, seconds, wake: (Mutex::new(false), Condvar::new()) })
    }

    /// Ask for a heartbeat now instead of at the next interval.
    pub fn beat_soon(&self) {
        *self.wake.0.lock().unwrap() = true;
        self.wake.1.notify_all();
    }

    /// Runs on its own thread, forever. A failure is logged once and retried more slowly.
    pub fn spawn(self: &Arc<Self>, service: Arc<Service>, runtime: tokio::runtime::Handle) {
        let this = self.clone();
        std::thread::spawn(move || {
            let mut failing = false;
            loop {
                let ok = this.beat(&service, &runtime);
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

    fn beat(&self, service: &Arc<Service>, runtime: &tokio::runtime::Handle) -> bool {
        let Some(body) = runtime.block_on(Self::body(service, self.port)) else { return false };
        ureq::post(&format!("{}/v1/agents/heartbeat", self.root)).timeout(Duration::from_secs(15)).set("Authorization", &format!("Bearer {}", self.token))
            .set("Content-Type", "application/json").send_string(&body.to_string()).is_ok_and(|r| r.status() == 204)
    }

    async fn body(service: &Arc<Service>, port: u16) -> Option<Value> {
        let facts = service.facts().await.ok()?;
        let workloads = service.workloads().await.ok()?;
        let mut body = json!({"facts": facts, "workloads": workloads, "agent_port": port});
        if let Some(version) = service.health().await.bundle_version {
            body["bundle_version"] = json!(version);
        }
        Some(body)
    }
}
