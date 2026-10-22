//! Bytes, errors and dropped packets from /proc/net/dev, all interfaces except loopback added together.
const LOOPBACK: &str = "lo";
const RECEIVED_FIELD: usize = 0;
const ERRORS_IN_FIELD: usize = 2;
const DROPS_IN_FIELD: usize = 3;
const SENT_FIELD: usize = 8;
const ERRORS_OUT_FIELD: usize = 10;
const DROPS_OUT_FIELD: usize = 11;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Counters {
    pub received: u64,
    pub sent: u64,
    pub errors_in: u64,
    pub errors_out: u64,
    pub drops_in: u64,
    pub drops_out: u64,
}

pub fn parse(text: &str) -> Counters {
    let mut counters = Counters::default();
    for line in text.lines() {
        let Some((name, rest)) = line.split_once(':') else { continue };
        if name.trim() == LOOPBACK {
            continue;
        }
        let fields: Vec<u64> = rest.split_whitespace().filter_map(|n| n.parse().ok()).collect();
        let at = |index: usize| fields.get(index).copied().unwrap_or(0);
        counters.received = counters.received.saturating_add(at(RECEIVED_FIELD));
        counters.sent = counters.sent.saturating_add(at(SENT_FIELD));
        counters.errors_in = counters.errors_in.saturating_add(at(ERRORS_IN_FIELD));
        counters.errors_out = counters.errors_out.saturating_add(at(ERRORS_OUT_FIELD));
        counters.drops_in = counters.drops_in.saturating_add(at(DROPS_IN_FIELD));
        counters.drops_out = counters.drops_out.saturating_add(at(DROPS_OUT_FIELD));
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

    const DEV: &str = "Inter-|   Rx    |  Tx\n face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n    lo: 9999 1 7 7 0 0 0 0 9999 1 7 7 0 0 0 0\n  eth0: 1000 10 1 2 0 0 0 0 400 5 3 4 0 0 0 0\n wlan0:  200 10 0 1 0 0 0 0 100 5 0 0 0 0 0 0\n";

    #[test]
    fn adds_every_interface_but_loopback() {
        let counters = parse(DEV);
        assert_eq!((counters.received, counters.sent), (1200, 500));
    }

    #[test]
    fn errors_and_drops_are_counted_in_both_directions() {
        let counters = parse(DEV);
        assert_eq!((counters.errors_in, counters.drops_in), (1, 3));
        assert_eq!((counters.errors_out, counters.drops_out), (3, 4));
    }

    #[test]
    fn rate_is_per_second_and_never_negative() {
        assert_eq!(rate(1000, 3000, 2.0), Some(1000.0));
        assert_eq!(rate(3000, 1000, 2.0), None);
    }
}
