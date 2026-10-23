//! The accounting of the GPU memory watchdog: pure, so a round is a function of what was measured.
use std::collections::{HashMap, HashSet};

/// Rounds in a row a container must be over its limit before it is stopped (a short spike is forgiven).
pub const OVER_ROUNDS_BEFORE_STOP: u32 = 3;

/// What the watchdog asks for after a round.
#[derive(Debug, PartialEq, Eq)]
pub struct Stop {
    pub instance: String,
    pub used_mib: u64,
    pub limit_mib: u64,
}

/// The limit in MiB of every running container that has one, by instance name.
pub type Limits = HashMap<String, u64>;
/// The GPU memory in MiB held by the programs of each container, by instance name.
pub type Usage = HashMap<String, u64>;

#[derive(Default)]
pub struct Tracker {
    over_rounds: HashMap<String, u32>,
    stop_asked: HashSet<String>,
}

impl Tracker {
    /// One round. `usage` is None when the card could not be read: nothing changes then. A container that is no longer in `limits`
    /// (stopped by hand, deleted, or stopped by us) is dropped, so a start later begins fresh.
    pub fn observe(&mut self, limits: &Limits, usage: Option<&Usage>) -> Vec<Stop> {
        let Some(usage) = usage else { return Vec::new() };
        self.over_rounds.retain(|instance, _| limits.contains_key(instance));
        self.stop_asked.retain(|instance| limits.contains_key(instance));
        let mut stops: Vec<Stop> = limits.iter().filter_map(|(instance, limit_mib)| self.judge(instance, *limit_mib, usage.get(instance).copied().unwrap_or(0))).collect();
        stops.sort_by(|a, b| a.instance.cmp(&b.instance));
        stops
    }

    /// The stop did not work: forget it, so the next over rounds ask again.
    pub fn stop_failed(&mut self, instance: &str) {
        self.stop_asked.remove(instance);
        self.over_rounds.remove(instance);
    }

    fn judge(&mut self, instance: &str, limit_mib: u64, used_mib: u64) -> Option<Stop> {
        if used_mib <= limit_mib {
            self.over_rounds.remove(instance);
            self.stop_asked.remove(instance);
            return None;
        }
        let rounds = self.over_rounds.entry(instance.to_string()).or_insert(0);
        *rounds += 1;
        if *rounds < OVER_ROUNDS_BEFORE_STOP || !self.stop_asked.insert(instance.to_string()) {
            return None;
        }
        Some(Stop { instance: instance.to_string(), used_mib, limit_mib })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table(items: &[(&str, u64)]) -> HashMap<String, u64> {
        items.iter().map(|(name, mib)| (name.to_string(), *mib)).collect()
    }

    fn names(stops: &[Stop]) -> Vec<&str> {
        stops.iter().map(|stop| stop.instance.as_str()).collect()
    }

    #[test]
    fn under_and_exactly_at_the_limit_are_never_over() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 4096)]);
        for used in [0, 1000, 4096] {
            for _ in 0..5 { assert!(tracker.observe(&limit, Some(&table(&[("ms-a", used)]))).is_empty()); }
        }
    }

    #[test]
    fn one_or_two_over_rounds_are_forgiven() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 4096)]);
        let over = table(&[("ms-a", 5000)]);
        let under = table(&[("ms-a", 100)]);
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert!(tracker.observe(&limit, Some(&under)).is_empty());
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert!(tracker.observe(&limit, Some(&under)).is_empty());
        assert!(tracker.observe(&limit, Some(&over)).is_empty(), "the counter started again");
    }

    #[test]
    fn three_over_rounds_stop_once_per_episode() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 4096)]);
        let over = table(&[("ms-a", 5325)]);
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert_eq!(tracker.observe(&limit, Some(&over)), [Stop { instance: "ms-a".into(), used_mib: 5325, limit_mib: 4096 }]);
        for _ in 0..5 { assert!(tracker.observe(&limit, Some(&over)).is_empty(), "no repeat"); }
    }

    #[test]
    fn a_failed_stop_is_asked_again_after_three_more_rounds() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 10)]);
        let over = table(&[("ms-a", 99)]);
        for _ in 0..2 { tracker.observe(&limit, Some(&over)); }
        assert_eq!(names(&tracker.observe(&limit, Some(&over))), ["ms-a"]);
        tracker.stop_failed("ms-a");
        for _ in 0..2 { assert!(tracker.observe(&limit, Some(&over)).is_empty()); }
        assert_eq!(names(&tracker.observe(&limit, Some(&over))), ["ms-a"]);
    }

    #[test]
    fn containers_are_independent() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 100), ("ms-b", 100)]);
        let mixed = table(&[("ms-a", 500), ("ms-b", 50)]);
        tracker.observe(&limit, Some(&mixed));
        tracker.observe(&limit, Some(&mixed));
        assert_eq!(names(&tracker.observe(&limit, Some(&mixed))), ["ms-a"]);
    }

    #[test]
    fn a_container_without_a_limit_is_never_touched() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 100)]);
        let big = table(&[("ms-free", 99999), ("ms-a", 10)]);
        for _ in 0..10 { assert!(tracker.observe(&limit, Some(&big)).is_empty()); }
    }

    #[test]
    fn a_failed_read_changes_nothing() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 100)]);
        let over = table(&[("ms-a", 500)]);
        tracker.observe(&limit, Some(&over));
        tracker.observe(&limit, Some(&over));
        for _ in 0..5 { assert!(tracker.observe(&limit, None).is_empty()); }
        assert_eq!(names(&tracker.observe(&limit, Some(&over))), ["ms-a"], "the counters were kept");
    }

    #[test]
    fn a_container_stopped_by_hand_is_dropped_and_starts_fresh() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 100)]);
        let over = table(&[("ms-a", 500)]);
        tracker.observe(&limit, Some(&over));
        tracker.observe(&limit, Some(&over));
        tracker.observe(&table(&[]), Some(&table(&[])));
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert!(tracker.observe(&limit, Some(&over)).is_empty());
        assert_eq!(names(&tracker.observe(&limit, Some(&over))), ["ms-a"]);
    }

    #[test]
    fn a_restart_after_a_stop_is_a_new_episode() {
        let mut tracker = Tracker::default();
        let limit = table(&[("ms-a", 100)]);
        let over = table(&[("ms-a", 500)]);
        for _ in 0..3 { tracker.observe(&limit, Some(&over)); }
        tracker.observe(&table(&[]), Some(&table(&[])));
        for _ in 0..2 { assert!(tracker.observe(&limit, Some(&over)).is_empty()); }
        assert_eq!(names(&tracker.observe(&limit, Some(&over))), ["ms-a"]);
    }
}
