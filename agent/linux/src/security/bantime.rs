//! How long fail2ban bans for, when its readable settings say so. Files are read in fail2ban's order (`jail.d/*.conf`, `jail.local`, `jail.d/*.local`),
//! a later file overrides an earlier one, and a value in `[sshd]` beats one in `[DEFAULT]`. Unknown, unreadable or permanent (negative) gives None.
use super::env::Environment;
use std::path::PathBuf;

const JAIL_DIRECTORY: &str = "/etc/fail2ban/jail.d";
const JAIL_LOCAL: &str = "/etc/fail2ban/jail.local";
const SSHD_SECTION: &str = "sshd";
const DEFAULT_SECTION: &str = "default";

pub fn seconds(env: &Environment) -> Option<i64> {
    let (mut default, mut sshd) = (None, None);
    for path in files(env) {
        let Ok(text) = std::fs::read_to_string(path) else {
            continue;
        };
        let (file_default, file_sshd) = values(&text);
        default = file_default.or(default);
        sshd = file_sshd.or(sshd);
    }
    sshd.or(default).filter(|seconds| *seconds > 0)
}

fn files(env: &Environment) -> Vec<PathBuf> {
    let mut listed: Vec<PathBuf> = std::fs::read_dir(env.at(JAIL_DIRECTORY))
        .into_iter()
        .flatten()
        .flatten()
        .map(|entry| entry.path())
        .collect();
    listed.sort();
    let extension = |path: &PathBuf, wanted: &str| {
        path.extension().and_then(|found| found.to_str()) == Some(wanted)
    };
    let mut ordered: Vec<PathBuf> = listed
        .iter()
        .filter(|path| extension(path, "conf"))
        .cloned()
        .collect();
    ordered.push(env.at(JAIL_LOCAL));
    ordered.extend(
        listed
            .iter()
            .filter(|path| extension(path, "local"))
            .cloned(),
    );
    ordered
}

/// The last `bantime` of the `[DEFAULT]` and of the `[sshd]` section in one file.
fn values(text: &str) -> (Option<i64>, Option<i64>) {
    let (mut section, mut default, mut sshd) = (String::new(), None, None);
    for line in text.lines().map(str::trim) {
        if let Some(name) = line
            .strip_prefix('[')
            .and_then(|rest| rest.strip_suffix(']'))
        {
            section = name.to_ascii_lowercase();
            continue;
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        if key.trim() != "bantime" {
            continue;
        }
        match section.as_str() {
            DEFAULT_SECTION => default = parse_duration(value.trim()),
            SSHD_SECTION => sshd = parse_duration(value.trim()),
            _ => {}
        }
    }
    (default, sshd)
}

/// `600`, `10m`, `1h`, `1d`, `1w` (also `30s`). Anything else, such as `%(x)s`, is unknown.
fn parse_duration(text: &str) -> Option<i64> {
    let text = text.split(['#', ';']).next()?.trim();
    let digits_end = text
        .find(|c: char| !(c.is_ascii_digit() || c == '-'))
        .unwrap_or(text.len());
    let number: i64 = text[..digits_end].parse().ok()?;
    let unit = match text[digits_end..].trim() {
        "" | "s" | "sec" => 1,
        "m" | "min" => 60,
        "h" | "hr" => 3600,
        "d" | "day" => 86_400,
        "w" | "week" => 604_800,
        _ => return None,
    };
    number.checked_mul(unit)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(files: &[(&str, &str)]) -> Option<i64> {
        let root = std::env::temp_dir().join(format!("ms-ban-{}", rand::random::<u64>()));
        for (path, text) in files {
            let target = root.join(path.trim_start_matches('/'));
            std::fs::create_dir_all(target.parent().unwrap()).unwrap();
            std::fs::write(target, text).unwrap();
        }
        std::fs::create_dir_all(&root).unwrap();
        let env = Environment {
            root: root.clone(),
            home: root.clone(),
            user: "u".into(),
            auth_log: root.join("a"),
            fail2ban_log: root.join("f"),
        };
        let found = seconds(&env);
        let _ = std::fs::remove_dir_all(root);
        found
    }

    #[test]
    fn durations() {
        for (text, expected) in [
            ("600", Some(600)),
            ("10m", Some(600)),
            ("1h", Some(3600)),
            ("2d", Some(172_800)),
            ("1w", Some(604_800)),
            ("30 s", Some(30)),
            ("1h # a day", Some(3600)),
            ("-1", Some(-1)),
            ("%(x)s", None),
            ("soon", None),
            ("", None),
        ] {
            assert_eq!(parse_duration(text), expected, "{text:?}");
        }
    }

    #[test]
    fn sshd_beats_default_and_later_files_beat_earlier_ones() {
        assert_eq!(
            read(&[(
                "/etc/fail2ban/jail.local",
                "[DEFAULT]\nbantime = 1h\n[sshd]\nenabled = true\n"
            )]),
            Some(3600)
        );
        assert_eq!(
            read(&[(
                "/etc/fail2ban/jail.local",
                "[DEFAULT]\nbantime = 1h\n[sshd]\nbantime = 10m\n"
            )]),
            Some(600)
        );
        let files = [
            ("/etc/fail2ban/jail.local", "[sshd]\nbantime = 10m\n"),
            (
                "/etc/fail2ban/jail.d/custom.local",
                "[sshd]\nbantime = 2h\n",
            ),
            (
                "/etc/fail2ban/jail.d/defaults-debian.conf",
                "[sshd]\nbantime = 5m\nenabled = true\n",
            ),
        ];
        assert_eq!(read(&files), Some(7200));
    }

    #[test]
    fn nothing_readable_or_a_permanent_ban_is_unknown() {
        assert_eq!(read(&[]), None);
        assert_eq!(
            read(&[("/etc/fail2ban/jail.local", "[sshd]\nbantime = -1\n")]),
            None
        );
        assert_eq!(
            read(&[("/etc/fail2ban/jail.local", "[nginx]\nbantime = 1h\n")]),
            None
        );
    }
}
