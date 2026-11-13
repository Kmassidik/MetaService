//! Bytes, errors and dropped packets from /proc/net/dev, all interfaces except loopback added together, and the primary interface (the one with the default route).
const LOOPBACK: &str = "lo";
const RECEIVED_FIELD: usize = 0;
const ERRORS_IN_FIELD: usize = 2;
const DROPS_IN_FIELD: usize = 3;
const SENT_FIELD: usize = 8;
const ERRORS_OUT_FIELD: usize = 10;
const DROPS_OUT_FIELD: usize = 11;
const ANY_ADDRESS: &str = "00000000";
const ROUTE_FLAG_UP: u32 = 0x1;
const HEX_RADIX: u32 = 16;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Counters {
    pub received: u64,
    pub sent: u64,
    pub errors_in: u64,
    pub errors_out: u64,
    pub drops_in: u64,
    pub drops_out: u64,
}

/// The primary interface: its name and its counters at one reading.
#[derive(Debug, Clone, PartialEq)]
pub struct Primary {
    pub name: String,
    pub counters: Counters,
}

impl Counters {
    /// Adds another reading to this one. Saturating, so a huge counter cannot panic.
    fn add(&mut self, other: Counters) {
        self.received = self.received.saturating_add(other.received);
        self.sent = self.sent.saturating_add(other.sent);
        self.errors_in = self.errors_in.saturating_add(other.errors_in);
        self.errors_out = self.errors_out.saturating_add(other.errors_out);
        self.drops_in = self.drops_in.saturating_add(other.drops_in);
        self.drops_out = self.drops_out.saturating_add(other.drops_out);
    }
}

/// The counters on one /proc/net/dev line, given the text after the interface name's colon.
fn line_counters(rest: &str) -> Counters {
    let fields: Vec<u64> = rest.split_whitespace().filter_map(|n| n.parse().ok()).collect();
    let at = |index: usize| fields.get(index).copied().unwrap_or(0);
    Counters {
        received: at(RECEIVED_FIELD),
        sent: at(SENT_FIELD),
        errors_in: at(ERRORS_IN_FIELD),
        errors_out: at(ERRORS_OUT_FIELD),
        drops_in: at(DROPS_IN_FIELD),
        drops_out: at(DROPS_OUT_FIELD),
    }
}

/// Counters of every interface in /proc/net/dev text except loopback, added together.
pub fn parse(text: &str) -> Counters {
    let mut total = Counters::default();
    for line in text.lines() {
        let Some((name, rest)) = line.split_once(':') else { continue };
        if name.trim() == LOOPBACK {
            continue;
        }
        total.add(line_counters(rest));
    }
    total
}

/// Counters of one named interface in /proc/net/dev text. None when that interface is not listed.
pub fn parse_interface(text: &str, name: &str) -> Option<Counters> {
    text.lines().find_map(|line| {
        let (interface, rest) = line.split_once(':')?;
        (interface.trim() == name).then(|| line_counters(rest))
    })
}

/// The interface of the default route in /proc/net/route text (the lowest metric wins). None when there is none.
pub fn default_interface(route_table: &str) -> Option<String> {
    route_table
        .lines()
        .filter_map(default_route)
        .min_by_key(|(_, metric)| *metric)
        .map(|(iface, _)| iface.to_string())
}

/// The interface and metric of one /proc/net/route row, when that row is an up default route. Other rows, the header and garbage give None.
fn default_route(line: &str) -> Option<(&str, u32)> {
    let fields: Vec<&str> = line.split_whitespace().collect();
    let [iface, destination, _gateway, flags, _refcount, _use, metric, mask, ..] = fields.as_slice() else { return None };
    let flags = u32::from_str_radix(flags, HEX_RADIX).ok()?;
    let metric = metric.parse::<u32>().ok()?;
    let is_default = *destination == ANY_ADDRESS && *mask == ANY_ADDRESS && flags & ROUTE_FLAG_UP != 0;
    is_default.then_some((*iface, metric))
}

/// The primary interface's name and counters. None when there is no default route or the route's interface is not in /proc/net/dev.
pub fn primary_reading(route_table: &str, dev_text: &str) -> Option<Primary> {
    let name = default_interface(route_table)?;
    let counters = parse_interface(dev_text, &name)?;
    Some(Primary { name, counters })
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
    const ROUTE_HEADER: &str = "Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n";
    const DOCKER_ROUTE: &str = "docker0\t0000A8C0\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n";
    const ENP_DEFAULT: &str = "enp5s0\t00000000\t0102A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n";

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

    #[test]
    fn one_named_interface_is_read_on_its_own() {
        let eth0 = parse_interface(DEV, "eth0").unwrap();
        assert_eq!((eth0.received, eth0.sent), (1000, 400));
    }

    #[test]
    fn a_missing_interface_is_none() {
        assert_eq!(parse_interface(DEV, "usb9"), None);
    }

    #[test]
    fn the_default_route_is_the_interface_that_is_not_a_bridge() {
        let table = format!("{ROUTE_HEADER}{DOCKER_ROUTE}{ENP_DEFAULT}");
        assert_eq!(default_interface(&table), Some("enp5s0".to_string()));
    }

    #[test]
    fn two_default_routes_pick_the_lowest_metric() {
        let wifi = "wlan0\t00000000\t0102A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0\n";
        let table = format!("{ROUTE_HEADER}{wifi}{ENP_DEFAULT}");
        assert_eq!(default_interface(&table), Some("enp5s0".to_string()));
    }

    #[test]
    fn no_default_route_is_none() {
        let down = "eth1\t00000000\t0102A8C0\t0002\t0\t0\t50\t00000000\t0\t0\t0\n";
        let table = format!("{ROUTE_HEADER}{DOCKER_ROUTE}{down}");
        assert_eq!(default_interface(&table), None);
    }

    #[test]
    fn garbage_rows_are_skipped_and_empty_text_is_none() {
        let table = format!("not a route at all\n\nenp5s0 xx yy zz\n{ENP_DEFAULT}");
        assert_eq!(default_interface(&table), Some("enp5s0".to_string()));
        assert_eq!(default_interface(""), None);
    }

    #[test]
    fn the_primary_reading_has_the_default_interfaces_counters() {
        let table = format!("{ROUTE_HEADER}{ENP_DEFAULT}");
        let dev = "  enp5s0: 700 1 0 0 0 0 0 0 300 1 0 0 0 0 0 0\n  docker0: 5000 1 0 0 0 0 0 0 4000 1 0 0 0 0 0 0\n";
        let primary = primary_reading(&table, dev).unwrap();
        assert_eq!((primary.name.as_str(), primary.counters.received, primary.counters.sent), ("enp5s0", 700, 300));
    }
}
