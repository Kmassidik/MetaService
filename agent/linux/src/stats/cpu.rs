//! CPU time from /proc/stat and the load average from /proc/loadavg.
use super::model::{one_decimal, Load, MAX_CORES};

/// Ticks spent working and in total since boot, for one core or for all of them.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Ticks {
    pub busy: u64,
    pub total: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CpuTimes {
    pub all: Ticks,
    pub cores: Vec<Ticks>,
}

const IDLE_FIELD: usize = 3;
const IOWAIT_FIELD: usize = 4;
const FIELDS_COUNTED: usize = 8; // user nice system idle iowait irq softirq steal

pub fn parse_times(text: &str) -> Option<CpuTimes> {
    let mut all = None;
    let mut cores = Vec::new();
    for line in text.lines() {
        let Some((label, rest)) = line.split_once(char::is_whitespace) else { continue };
        if label == "cpu" {
            all = parse_ticks(rest);
        } else if label.starts_with("cpu") && cores.len() < MAX_CORES {
            cores.extend(parse_ticks(rest));
        }
    }
    Some(CpuTimes { all: all?, cores })
}

fn parse_ticks(fields: &str) -> Option<Ticks> {
    let numbers: Vec<u64> = fields.split_whitespace().take(FIELDS_COUNTED).map(|n| n.parse().ok()).collect::<Option<_>>()?;
    let total: u64 = numbers.iter().sum();
    let idle = numbers.get(IDLE_FIELD)? + numbers.get(IOWAIT_FIELD)?;
    Some(Ticks { busy: total.saturating_sub(idle), total })
}

/// Percent busy between two readings, 0..100 with one decimal. No time passed counts as 0.
pub fn percent_between(before: Ticks, after: Ticks) -> f64 {
    let total = after.total.saturating_sub(before.total);
    if total == 0 {
        return 0.0;
    }
    let busy = after.busy.saturating_sub(before.busy);
    one_decimal((busy as f64 / total as f64 * 100.0).clamp(0.0, 100.0))
}

pub fn parse_load(text: &str) -> Load {
    let mut numbers = text.split_whitespace().map(|n| n.parse::<f64>().ok().filter(|v| v.is_finite() && *v >= 0.0));
    Load { one: numbers.next().flatten(), five: numbers.next().flatten(), fifteen: numbers.next().flatten() }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STAT: &str = "cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 50 0 50 350 50 0 0 0 0 0\ncpu1 50 0 50 350 50 0 0 0 0 0\nintr 5\n";

    #[test]
    fn reads_total_and_every_core() {
        let times = parse_times(STAT).unwrap();
        assert_eq!(times.cores.len(), 2);
        assert_eq!(times.all, Ticks { busy: 200, total: 1000 });
    }

    #[test]
    fn missing_or_broken_lines_give_nothing() {
        assert!(parse_times("intr 5\n").is_none());
        assert!(parse_times("cpu  1 2 x 4 5\n").is_none());
    }

    #[test]
    fn percent_is_busy_share_of_the_gap() {
        let before = Ticks { busy: 200, total: 1000 };
        assert_eq!(percent_between(before, Ticks { busy: 300, total: 1200 }), 50.0);
        assert_eq!(percent_between(before, before), 0.0);
        assert_eq!(percent_between(before, Ticks { busy: 100, total: 900 }), 0.0, "a counter that went back is not negative");
    }

    #[test]
    fn load_average_with_a_bad_field_is_null_for_it() {
        assert_eq!(parse_load("0.50 1.25 2.00 1/200 99"), Load { one: Some(0.5), five: Some(1.25), fifteen: Some(2.0) });
        assert_eq!(parse_load("x 1.0"), Load { one: None, five: Some(1.0), fifteen: None });
    }
}
