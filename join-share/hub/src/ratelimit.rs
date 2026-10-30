//! Per-IP fixed-window request limit.
use std::collections::HashMap;
use std::sync::Mutex;

const PRUNE_ABOVE: usize = 10_000;

pub struct RateLimiter {
    limit: u32,
    window_secs: i64,
    hits: Mutex<HashMap<String, (i64, u32)>>,
}

impl RateLimiter {
    pub fn new(limit: u32, window_secs: i64) -> Self {
        Self { limit, window_secs, hits: Mutex::new(HashMap::new()) }
    }

    pub fn allow(&self, ip: &str, now: i64) -> bool {
        let mut hits = self.hits.lock().unwrap_or_else(|e| e.into_inner());
        if hits.len() > PRUNE_ABOVE {
            hits.retain(|_, (start, _)| now - *start < self.window_secs);
        }
        let entry = hits.entry(ip.to_string()).or_insert((now, 0));
        if now - entry.0 >= self.window_secs {
            *entry = (now, 0);
        }
        entry.1 += 1;
        entry.1 <= self.limit
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn blocks_after_the_limit_then_resets() {
        let limiter = RateLimiter::new(3, 60);
        assert!((0..3).all(|_| limiter.allow("1.1.1.1", 100)));
        assert!(!limiter.allow("1.1.1.1", 101));
        assert!(limiter.allow("2.2.2.2", 101));
        assert!(limiter.allow("1.1.1.1", 160));
    }
}
