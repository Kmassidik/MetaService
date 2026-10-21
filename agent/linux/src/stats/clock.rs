//! The wall-clock time as the contract writes it: `YYYY-MM-DDTHH:MM:SSZ`.
const SECONDS_PER_DAY: u64 = 86_400;
const DAYS_FROM_YEAR_0_TO_1970: i64 = 719_468;
const DAYS_PER_ERA: i64 = 146_097;

pub fn iso8601(unix_seconds: u64) -> String {
    let days = (unix_seconds / SECONDS_PER_DAY) as i64;
    let rest = unix_seconds % SECONDS_PER_DAY;
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z", rest / 3600, rest % 3600 / 60, rest % 60)
}

/// Howard Hinnant's days-to-date rule.
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + DAYS_FROM_YEAR_0_TO_1970;
    let era = z.div_euclid(DAYS_PER_ERA);
    let day_of_era = z.rem_euclid(DAYS_PER_ERA);
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted_month = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * shifted_month + 2) / 5 + 1;
    let month = if shifted_month < 10 { shifted_month + 3 } else { shifted_month - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_moments() {
        assert_eq!(iso8601(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601(1_782_000_000), "2026-06-21T00:00:00Z");
        assert_eq!(iso8601(951_827_696), "2000-02-29T12:34:56Z");
    }
}
