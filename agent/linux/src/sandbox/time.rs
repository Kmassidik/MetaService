//! Times as the contract writes them: `YYYY-MM-DDTHH:MM:SSZ`, read strictly and written the same way.
use regex::Regex;
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

/// What the contract accepts, and nothing else: no fractions, no offset, no lowercase.
const ISO8601: &str = r"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$";
const SECONDS_PER_DAY: i64 = 86_400;
const DAYS_FROM_YEAR_0_TO_1970: i64 = 719_468;
const DAYS_PER_ERA: i64 = 146_097;

/// The moment now, in whole seconds since 1970. Seconds are enough: the contract's times have no fractions.
pub fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|since| since.as_secs()).unwrap_or(0)
}

/// Where the time is written the way the contract writes it (the monitor already owns that rule).
pub use crate::stats::iso8601;

/// The seconds since 1970 of a contract time, or None when the text is not exactly one.
pub fn parse(text: &str) -> Option<u64> {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    let found = PATTERN.get_or_init(|| Regex::new(ISO8601).unwrap()).captures(text)?;
    let field = |index: usize| found[index].parse::<i64>().ok();
    let (year, month, day, hour, minute, second) = (field(1)?, field(2)?, field(3)?, field(4)?, field(5)?, field(6)?);
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    let days = days_from_civil(year, month, day);
    let seconds = days * SECONDS_PER_DAY + hour * 3600 + minute * 60 + second;
    u64::try_from(seconds).ok()
}

/// Howard Hinnant's date-to-days rule, the other way round from the one the monitor uses.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year.rem_euclid(400);
    let shifted_month = if month > 2 { month - 3 } else { month + 9 };
    let day_of_year = (153 * shifted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * DAYS_PER_ERA + day_of_era - DAYS_FROM_YEAR_0_TO_1970
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_contract_time_comes_back_as_the_same_second() {
        for moment in [0, 1_782_000_000, 951_827_696, 1_790_000_000] {
            assert_eq!(parse(&iso8601(moment)), Some(moment), "{}", iso8601(moment));
        }
        assert_eq!(parse("2026-10-24T09:30:00Z"), Some(1_792_834_200));
    }

    #[test]
    fn anything_else_is_not_a_time() {
        for bad in ["", "2026-10-24T09:30:00", "2026-10-24T09:30:00.5Z", "2026-10-24 09:30:00Z", "2026-13-24T09:30:00Z", "2026-10-32T09:30:00Z",
                    "2026-10-24T24:00:00Z", "2026-10-24T09:60:00Z", "2026-10-24T09:30:60Z", "26-10-24T09:30:00Z", "2026-10-24t09:30:00z"] {
            assert_eq!(parse(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn now_is_a_time_the_contract_takes() {
        assert!(parse(&iso8601(now())).is_some());
    }
}
