//! Everything the HTTP handlers share.
use crate::clock::Clock;
use crate::config::Config;
use crate::peers::WgControl;
use crate::ratelimit::RateLimiter;
use crate::store::Store;
use std::sync::{Arc, Mutex};

pub struct AppState {
    pub config: Config,
    pub store: Store,
    pub wg: Arc<dyn WgControl>,
    pub clock: Clock,
    pub hub_public_key: String,
    pub admin_key: String,
    pub limiter: RateLimiter,
    /// Approval and peer removal change WireGuard and two databases; one at a time.
    pub change_lock: Mutex<()>,
}

pub type Shared = Arc<AppState>;

impl AppState {
    pub fn now(&self) -> i64 {
        (self.clock)()
    }
}
