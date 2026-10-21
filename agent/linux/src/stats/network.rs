//! Bytes in and out from /proc/net/dev, all interfaces except loopback added together.
const LOOPBACK: &str = "lo";
const RECEIVED_FIELD: usize = 0;
const SENT_FIELD: usize = 8;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Counters {
    pub received: u64,
    pub sent: u64,
}

pub fn parse(text: &str) -> Counters {
    let mut counters = Counters { received: 0, sent: 0 };
    for line in text.lines() {
        let Some((name, rest)) = line.split_once(':') else { continue };
        if name.trim() == LOOPBACK {
            continue;
        }
        let fields: Vec<u64> = rest.split_whitespace().filter_map(|n| n.parse().ok()).collect();
        counters.received = counters.received.saturating_add(fields.get(RECEIVED_FIELD).copied().unwrap_or(0));
        counters.sent = counters.sent.saturating_add(fields.get(SENT_FIELD).copied().unwrap_or(0));
    }
    counters
}

/// Bytes per second between two readings. A counter that went backwards (an interface went away) is None.
pub fn rate(before: u64, after: u64, seconds: f64) -> Option<f64> {
    let gained = after.checked_sub(before)?;
    Some(super::model::one_decimal(gained as f64 / seconds))
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEV: &str = "Inter-|   Rx    |  Tx\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n    lo: 9999 1 0 0 0 0 0 0 9999 1 0 0 0 0 0 0\n  eth0: 1000 10 0 0 0 0 0 0 400 5 0 0 0 0 0 0\n wlan0:  200 10 0 0 0 0 0 0 100 5 0 0 0 0 0 0\n";

    #[test]
    fn adds_every_interface_but_loopback() {
        assert_eq!(parse(DEV), Counters { received: 1200, sent: 500 });
    }

    #[test]
    fn rate_is_per_second_and_never_negative() {
        assert_eq!(rate(1000, 3000, 2.0), Some(1000.0));
        assert_eq!(rate(3000, 1000, 2.0), None);
    }
}
