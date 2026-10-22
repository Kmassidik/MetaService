//! CPU time from /proc/stat and the load average from /proc/loadavg.
use super::model::{one_decimal, CpuBreakdown, Load, MAX_CORES};

/// Ticks spent working and in total since boot, for one core or for all of them.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Ticks {
    pub busy: u64,
    pub total: u64,
}

/// Every state /proc/stat counts, in ticks since boot (guest time is already inside user).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Fields {
    pub user: u64,
    pub nice: u64,
    pub system: u64,
    pub idle: u64,
    pub iowait: u64,
    pub irq: u64,
    pub softirq: u64,
    pub steal: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CpuTimes {
    pub all: Ticks,
    pub fields: Fields,
    pub cores: Vec<Ticks>,
    /// The number after "cpu" for each entry of `cores` (offline CPUs leave gaps).
    pub ids: Vec<usize>,
}

const IDLE_FIELD: usize = 3;
const IOWAIT_FIELD: usize = 4;
const FIELDS_COUNTED: usize = 8; // user nice system idle iowait irq softirq steal

pub fn parse_times(text: &str) -> Option<CpuTimes> {
    let mut all = None;
    let mut cores = Vec::new();
    let mut ids = Vec::new();
    for line in text.lines() {
        let Some((label, rest)) = line.split_once(char::is_whitespace) else { continue };
        if label == "cpu" {
            all = parse_numbers(rest);
            continue;
        }
        let Some(id) = label.strip_prefix("cpu").and_then(|n| n.parse::<usize>().ok()) else { continue };
        let Some(numbers) = parse_numbers(rest).filter(|_| cores.len() < MAX_CORES) else { continue };
        cores.push(ticks_of(&numbers));
        ids.push(id);
    }
    let all = all?;
    Some(CpuTimes { all: ticks_of(&all), fields: fields_of(&all), cores, ids })
}

fn parse_numbers(fields: &str) -> Option<Vec<u64>> {
    let numbers: Vec<u64> = fields.split_whitespace().take(FIELDS_COUNTED).map(|n| n.parse().ok()).collect::<Option<_>>()?;
    (numbers.len() > IOWAIT_FIELD).then_some(numbers)
}

fn ticks_of(numbers: &[u64]) -> Ticks {
    let total: u64 = numbers.iter().sum();
    let idle = numbers[IDLE_FIELD] + numbers[IOWAIT_FIELD];
    Ticks { busy: total.saturating_sub(idle), total }
}

/// Old kernels give fewer than eight numbers: the missing ones count as 0 ticks.
fn fields_of(numbers: &[u64]) -> Fields {
    let at = |index: usize| numbers.get(index).copied().unwrap_or(0);
    Fields { user: at(0), nice: at(1), system: at(2), idle: at(3), iowait: at(4), irq: at(5), softirq: at(6), steal: at(7) }
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

/// Each state's share of the ticks between two readings, one decimal. No time passed: None.
pub fn breakdown_between(before: &Fields, after: &Fields) -> Option<CpuBreakdown> {
    let gap = |now: u64, then: u64| now.saturating_sub(then);
    let parts = [
        gap(after.user, before.user),
        gap(after.nice, before.nice),
        gap(after.system, before.system),
        gap(after.idle, before.idle),
        gap(after.iowait, before.iowait),
        gap(after.irq, before.irq),
        gap(after.softirq, before.softirq),
        gap(after.steal, before.steal),
    ];
    let total: u64 = parts.iter().sum();
    if total == 0 {
        return None;
    }
    let share = |part: u64| one_decimal(part as f64 / total as f64 * 100.0);
    Some(CpuBreakdown {
        user: share(parts[0]),
        nice: share(parts[1]),
        system: share(parts[2]),
        idle: share(parts[3]),
        iowait: share(parts[4]),
        irq: share(parts[5]),
        softirq: share(parts[6]),
        steal: share(parts[7]),
    })
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
    fn ids_follow_the_cpu_numbers_so_offline_gaps_are_kept() {
        let times = parse_times("cpu  4 0 0 0 0 0 0 0\ncpu0 1 0 0 0 0 0 0 0\ncpu2 3 0 0 0 0 0 0 0\n").unwrap();
        assert_eq!(times.ids, vec![0, 2]);
    }

    #[test]
    fn breakdown_is_each_states_share_of_the_gap() {
        let before = Fields { user: 100, idle: 900, ..Fields::default() };
        let after = Fields { user: 150, system: 25, idle: 1000, iowait: 25, ..before };
        let breakdown = breakdown_between(&before, &after).unwrap();
        assert_eq!((breakdown.user, breakdown.system, breakdown.idle, breakdown.iowait), (25.0, 12.5, 50.0, 12.5));
        assert_eq!(breakdown.steal, 0.0);
        assert!(breakdown_between(&before, &before).is_none(), "no time passed is not an answer");
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
