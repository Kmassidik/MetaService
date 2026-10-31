//! Times in log lines, read without a date library. Two shapes start the lines of the logs we read:
//! `2026-11-01T00:03:12.123456+07:00 host ...` (also `2026-11-01 00:03:12,345 ...` of fail2ban, with no zone) and the classic `Nov  1 00:03:12 host ...`.
use regex::Regex;
use std::sync::OnceLock;

const SECONDS_PER_DAY: i64 = 86_400;
/// A classic line carries no year; one dated later than this past now belongs to the year before.
const FUTURE_TOLERANCE_SECONDS: i64 = SECONDS_PER_DAY;
const YEAR_DIGITS: usize = 4;
const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const ISO_LINE: &str = r"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:[.,]\d+)?(Z|[+-]\d{2}(?::?\d{2})?)?\s+(.*)$";
const CLASSIC_LINE: &str = r"^([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(.*)$";

/// A date and time on a wall clock, as written in a line.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Civil {
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub second: i64,
}

/// How a wall clock of this machine becomes seconds since 1970 (None when it cannot). Tests give a fixed one.
pub type Zone = fn(&Civil) -> Option<i64>;

/// A timestamp read from the start of a line, and the rest of the line after it.
pub struct Stamped<'a> {
    pub epoch: i64,
    pub rest: &'a str,
}

impl Civil {
    pub fn as_utc(&self) -> i64 {
        crate::sandbox::time::days_from_civil(self.year, self.month, self.day) * SECONDS_PER_DAY
            + self.hour * 3600
            + self.minute * 60
            + self.second
    }

    fn is_valid(&self) -> bool {
        (1..=12).contains(&self.month)
            && (1..=31).contains(&self.day)
            && (0..=23).contains(&self.hour)
            && (0..=59).contains(&self.minute)
            && (0..=60).contains(&self.second)
    }
}

/// The machine's own zone, through the C library (it follows TZ and daylight saving).
pub fn system_zone(civil: &Civil) -> Option<i64> {
    // SAFETY: an all-zero `tm` is a valid value; `mktime` only reads and normalises the struct we own.
    let mut broken: libc::tm = unsafe { std::mem::zeroed() };
    broken.tm_year = (civil.year - 1900) as libc::c_int;
    broken.tm_mon = (civil.month - 1) as libc::c_int;
    broken.tm_mday = civil.day as libc::c_int;
    broken.tm_hour = civil.hour as libc::c_int;
    broken.tm_min = civil.minute as libc::c_int;
    broken.tm_sec = civil.second as libc::c_int;
    broken.tm_isdst = -1;
    // SAFETY: see above; `broken` outlives the call.
    let made = unsafe { libc::mktime(&mut broken) };
    (made != -1).then_some(made as i64)
}

/// Reads the time at the start of `line`. `now` decides the year of a classic line; `zone` places lines that carry no offset.
pub fn stamp(line: &str, now: i64, zone: Zone) -> Option<Stamped<'_>> {
    iso_stamp(line, zone).or_else(|| classic_stamp(line, now, zone))
}

fn iso_stamp(line: &str, zone: Zone) -> Option<Stamped<'_>> {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    let found = PATTERN
        .get_or_init(|| Regex::new(ISO_LINE).expect("constant pattern"))
        .captures(line)?;
    let number = |index: usize| found[index].parse::<i64>().ok();
    let civil = Civil {
        year: number(1)?,
        month: number(2)?,
        day: number(3)?,
        hour: number(4)?,
        minute: number(5)?,
        second: number(6)?,
    };
    if !civil.is_valid() {
        return None;
    }
    let epoch = match found.get(7) {
        Some(offset) => civil.as_utc() - offset_seconds(offset.as_str())?,
        None => zone(&civil)?,
    };
    Some(Stamped {
        epoch,
        rest: found.get(8)?.as_str(),
    })
}

/// `Z`, `+07:00`, `+0700` or `+07`, as seconds east of UTC.
fn offset_seconds(text: &str) -> Option<i64> {
    if text == "Z" {
        return Some(0);
    }
    let sign = if text.starts_with('-') { -1 } else { 1 };
    let digits: String = text[1..].chars().filter(char::is_ascii_digit).collect();
    let hours: i64 = digits.get(..2)?.parse().ok()?;
    let minutes: i64 = digits.get(2..4).map_or(Some(0), |part| part.parse().ok())?;
    Some(sign * (hours * 3600 + minutes * 60))
}

fn classic_stamp(line: &str, now: i64, zone: Zone) -> Option<Stamped<'_>> {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    let found = PATTERN
        .get_or_init(|| Regex::new(CLASSIC_LINE).expect("constant pattern"))
        .captures(line)?;
    let month = MONTHS.iter().position(|name| *name == &found[1])? as i64 + 1;
    let number = |index: usize| found[index].parse::<i64>().ok();
    let mut civil = Civil {
        year: year_of(now)?,
        month,
        day: number(2)?,
        hour: number(3)?,
        minute: number(4)?,
        second: number(5)?,
    };
    if !civil.is_valid() {
        return None;
    }
    let mut epoch = zone(&civil)?;
    if epoch > now + FUTURE_TOLERANCE_SECONDS {
        civil.year -= 1;
        epoch = zone(&civil)?;
    }
    Some(Stamped {
        epoch,
        rest: found.get(6)?.as_str(),
    })
}

fn year_of(epoch: i64) -> Option<i64> {
    crate::stats::iso8601(u64::try_from(epoch).ok()?)
        .get(..YEAR_DIGITS)?
        .parse()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_793_491_200; // 2026-11-01T00:00:00Z

    fn plus_seven(civil: &Civil) -> Option<i64> {
        Some(civil.as_utc() - 7 * 3600)
    }

    #[test]
    fn iso_lines_honour_their_own_offset() {
        let cases = [
            (
                "2026-11-01T00:03:12.123456+07:00 host sshd[1]: x",
                NOW - 7 * 3600 + 192,
                "host sshd[1]: x",
            ),
            ("2026-11-01T00:03:12+0000 host y", NOW + 192, "host y"),
            ("2026-11-01T00:03:12Z host y", NOW + 192, "host y"),
            ("2026-10-31T20:00:00-04:00 h", NOW, "h"),
        ];
        for (line, epoch, rest) in cases {
            let found = stamp(line, NOW, plus_seven).unwrap_or_else(|| panic!("{line}"));
            assert_eq!((found.epoch, found.rest), (epoch, rest), "{line}");
        }
    }

    #[test]
    fn a_line_without_an_offset_uses_the_machines_zone() {
        let found = stamp(
            "2026-11-01 00:03:12,345 fail2ban.actions [9]: NOTICE [sshd] Ban 1.2.3.4",
            NOW,
            plus_seven,
        )
        .unwrap();
        assert_eq!(found.epoch, NOW - 7 * 3600 + 192);
        assert!(found.rest.starts_with("fail2ban.actions"));
    }

    #[test]
    fn classic_lines_infer_the_year_and_go_back_one_when_it_would_be_the_future() {
        let found = stamp("Nov  1 00:03:12 host sshd[5]: hi", NOW, plus_seven).unwrap();
        assert_eq!(
            (found.epoch, found.rest),
            (NOW - 7 * 3600 + 192, "host sshd[5]: hi")
        );
        let december = stamp("Dec 31 23:59:59 host x", NOW, plus_seven).unwrap();
        assert_eq!(
            december.epoch,
            1_767_225_599 - 7 * 3600,
            "December of 2025, not of next year"
        );
    }

    #[test]
    fn garbage_has_no_time() {
        for line in [
            "",
            "hello world",
            "2026-13-01T00:00:00Z h",
            "Foo  1 00:00:00 h",
            "Nov 40 00:00:00 h",
            "2026-11-01T25:00:00Z h",
            "\u{0}\u{1}",
        ] {
            assert!(stamp(line, NOW, plus_seven).is_none(), "{line:?}");
        }
    }

    #[test]
    fn the_system_zone_places_a_wall_clock() {
        let civil = Civil {
            year: 2026,
            month: 11,
            day: 1,
            hour: 12,
            minute: 0,
            second: 0,
        };
        let placed = system_zone(&civil).unwrap();
        assert!((placed - civil.as_utc()).abs() <= 15 * 3600);
    }
}
