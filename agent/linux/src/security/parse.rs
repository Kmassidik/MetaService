//! One log line (after its timestamp) into what happened. Pure: no files, no clock.
use super::model::Method;
use super::text;
use regex::Regex;
use std::sync::OnceLock;

/// Whether a failed line is one try at a password (counted each) or the summary of a connection that went wrong (one try at least).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Attempt {
    Try,
    Summary,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Parsed {
    Failed {
        user: Option<String>,
        address: Option<String>,
        port: Option<u16>,
        attempt: Attempt,
        why: &'static str,
    },
    Login {
        user: Option<String>,
        address: Option<String>,
        method: Option<Method>,
    },
    Blocked {
        address: Option<String>,
        jail: String,
    },
    Unblocked {
        address: Option<String>,
        jail: String,
    },
}

const SSHD_PREFIX: &str = r"^\S+\s+sshd(?:-session)?\[\d+\]:\s+(.*)$";
const FAIL2BAN_LINE: &str = r"\[(sshd[\w-]*)\]\s+(Ban|Restore Ban|Unban)\s+(\S+)";
/// How each sshd message shape is told apart. The first capture groups are named; a shape lacks the groups it does not carry.
const SSHD_SHAPES: [(&str, &str, Attempt); 5] = [
    (
        r"^Failed \S+ for (?:invalid user )?(?P<user>\S+) from (?P<address>\S+) port (?P<port>\d+)",
        "failed login",
        Attempt::Try,
    ),
    (
        r"^Invalid user (?P<user>\S*) from (?P<address>\S+)(?: port (?P<port>\d+))?",
        "unknown user",
        Attempt::Summary,
    ),
    (
        r"^(?:Connection closed by|Disconnected from) (?:invalid|authenticating) user (?P<user>\S+) (?P<address>\S+) port (?P<port>\d+).*\[preauth\]",
        "closed before login",
        Attempt::Summary,
    ),
    (
        r"^maximum authentication attempts exceeded for (?:invalid user )?(?P<user>\S+) from (?P<address>\S+) port (?P<port>\d+)",
        "too many tries",
        Attempt::Summary,
    ),
    (
        r"^Unable to negotiate with (?P<address>\S+) port (?P<port>\d+):",
        "no common settings",
        Attempt::Summary,
    ),
];
const ACCEPTED: &str =
    r"^Accepted (?P<method>\S+) for (?P<user>\S+) from (?P<address>\S+) port \d+";

fn shapes() -> &'static Vec<(Regex, &'static str, Attempt)> {
    static SHAPES: OnceLock<Vec<(Regex, &'static str, Attempt)>> = OnceLock::new();
    SHAPES.get_or_init(|| {
        SSHD_SHAPES
            .iter()
            .map(|(pattern, why, attempt)| {
                (
                    Regex::new(pattern).expect("constant pattern"),
                    *why,
                    *attempt,
                )
            })
            .collect()
    })
}

/// `rest` is the line after its timestamp, such as `host sshd[12]: Failed password for ...` or `fail2ban.actions [9]: NOTICE [sshd] Ban 1.2.3.4`.
pub fn parse(rest: &str) -> Option<Parsed> {
    static PREFIX: OnceLock<Regex> = OnceLock::new();
    match PREFIX
        .get_or_init(|| Regex::new(SSHD_PREFIX).expect("constant pattern"))
        .captures(rest)
    {
        Some(found) => parse_sshd(&found[1]),
        None => parse_fail2ban(rest),
    }
}

fn parse_sshd(message: &str) -> Option<Parsed> {
    if let Some(parsed) = parse_accepted(message) {
        return Some(parsed);
    }
    let (found, why, attempt) = shapes().iter().find_map(|(pattern, why, attempt)| {
        pattern
            .captures(message)
            .map(|found| (found, *why, *attempt))
    })?;
    let group = |name: &str| found.name(name).map(|m| m.as_str());
    Some(Parsed::Failed {
        user: group("user").and_then(text::user),
        address: group("address").and_then(text::address),
        port: group("port").and_then(|port| port.parse().ok()),
        attempt,
        why,
    })
}

fn parse_accepted(message: &str) -> Option<Parsed> {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    let found = PATTERN
        .get_or_init(|| Regex::new(ACCEPTED).expect("constant pattern"))
        .captures(message)?;
    let method = match &found["method"] {
        "publickey" => Some(Method::Key),
        "password" | "keyboard-interactive/pam" => Some(Method::Password),
        _ => None,
    };
    Some(Parsed::Login {
        user: text::user(&found["user"]),
        address: text::address(&found["address"]),
        method,
    })
}

fn parse_fail2ban(rest: &str) -> Option<Parsed> {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    let found = PATTERN
        .get_or_init(|| Regex::new(FAIL2BAN_LINE).expect("constant pattern"))
        .captures(rest)?;
    let (jail, address) = (found[1].to_string(), text::address(&found[3]));
    Some(if &found[2] == "Unban" {
        Parsed::Unblocked { address, jail }
    } else {
        Parsed::Blocked { address, jail }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fields(line: &str) -> (Option<String>, Option<String>, Option<u16>, Attempt) {
        match parse(line) {
            Some(Parsed::Failed {
                user,
                address,
                port,
                attempt,
                ..
            }) => (user, address, port, attempt),
            other => panic!("{line}: {other:?}"),
        }
    }

    fn some(text: &str) -> Option<String> {
        Some(text.to_string())
    }

    #[test]
    fn every_failed_shape_of_ubuntu_24_04() {
        let cases = [
            ("h sshd[1]: Failed password for root from 203.0.113.9 port 4242 ssh2", some("root"), "203.0.113.9", Some(4242), Attempt::Try),
            ("h sshd[1]: Failed password for invalid user admin from 198.51.100.7 port 5 ssh2", some("admin"), "198.51.100.7", Some(5), Attempt::Try),
            ("h sshd[1]: Failed publickey for kurnia from 203.0.113.9 port 22 ssh2: RSA SHA256:abc", some("kurnia"), "203.0.113.9", Some(22), Attempt::Try),
            ("h sshd[1]: Invalid user oracle from 203.0.113.10 port 50000", some("oracle"), "203.0.113.10", Some(50000), Attempt::Summary),
            ("h sshd[1]: Invalid user  from 203.0.113.10 port 50001", None, "203.0.113.10", Some(50001), Attempt::Summary),
            ("h sshd[1]: Connection closed by invalid user test 203.0.113.11 port 6000 [preauth]", some("test"), "203.0.113.11", Some(6000), Attempt::Summary),
            ("h sshd[1]: Connection closed by authenticating user root 203.0.113.11 port 6001 [preauth]", some("root"), "203.0.113.11", Some(6001), Attempt::Summary),
            ("h sshd[1]: Disconnected from invalid user git 203.0.113.12 port 7000 [preauth]", some("git"), "203.0.113.12", Some(7000), Attempt::Summary),
            ("h sshd[1]: Disconnected from authenticating user root 203.0.113.12 port 7001 [preauth]", some("root"), "203.0.113.12", Some(7001), Attempt::Summary),
            ("h sshd[1]: maximum authentication attempts exceeded for invalid user a from 203.0.113.13 port 8000 ssh2 [preauth]", some("a"), "203.0.113.13", Some(8000), Attempt::Summary),
            ("h sshd[1]: maximum authentication attempts exceeded for root from 203.0.113.13 port 8001 ssh2 [preauth]", some("root"), "203.0.113.13", Some(8001), Attempt::Summary),
            ("h sshd[1]: Unable to negotiate with 203.0.113.14 port 9000: no matching key exchange method found. Their offer: x [preauth]", None, "203.0.113.14", Some(9000), Attempt::Summary),
            ("h sshd-session[1]: Failed password for root from 2001:db8::5 port 1 ssh2", some("root"), "2001:db8::5", Some(1), Attempt::Try),
        ];
        for (line, user, address, port, attempt) in cases {
            assert_eq!(fields(line), (user, some(address), port, attempt), "{line}");
        }
    }

    #[test]
    fn logins_by_key_and_by_password() {
        let key = parse("h sshd[1]: Accepted publickey for kurnia from 203.0.113.1 port 55 ssh2: ED25519 SHA256:xyz");
        assert_eq!(
            key,
            Some(Parsed::Login {
                user: some("kurnia"),
                address: some("203.0.113.1"),
                method: Some(Method::Key)
            })
        );
        let password = parse("h sshd[1]: Accepted password for bob from fe80::1 port 55 ssh2");
        assert_eq!(
            password,
            Some(Parsed::Login {
                user: some("bob"),
                address: some("fe80::1"),
                method: Some(Method::Password)
            })
        );
        let other = parse("h sshd[1]: Accepted hostbased for bob from 10.0.0.1 port 55 ssh2");
        assert_eq!(
            other,
            Some(Parsed::Login {
                user: some("bob"),
                address: some("10.0.0.1"),
                method: None
            })
        );
    }

    #[test]
    fn fail2ban_bans_and_unbans_and_ignores_found() {
        let ban = parse("fail2ban.actions [812]: NOTICE [sshd] Ban 203.0.113.9");
        assert_eq!(
            ban,
            Some(Parsed::Blocked {
                address: some("203.0.113.9"),
                jail: "sshd".into()
            })
        );
        let wide = parse("fail2ban.actions        [812]: NOTICE  [sshd] Ban 2001:db8::9");
        assert_eq!(
            wide,
            Some(Parsed::Blocked {
                address: some("2001:db8::9"),
                jail: "sshd".into()
            })
        );
        let unban = parse("fail2ban.actions [812]: NOTICE [sshd] Unban 203.0.113.9");
        assert_eq!(
            unban,
            Some(Parsed::Unblocked {
                address: some("203.0.113.9"),
                jail: "sshd".into()
            })
        );
        assert!(matches!(
            parse("fail2ban.actions [812]: NOTICE [sshd] Restore Ban 1.2.3.4"),
            Some(Parsed::Blocked { .. })
        ));
        assert_eq!(
            parse("fail2ban.filter [812]: INFO [sshd] Found 203.0.113.9 - 2026-11-01 00:03:12"),
            None
        );
        assert_eq!(
            parse("fail2ban.actions [812]: NOTICE [nginx] Ban 203.0.113.9"),
            None
        );
    }

    #[test]
    fn noise_and_garbage_are_not_events() {
        for line in [
            "",
            "h sshd[1]: Server listening on 0.0.0.0 port 22.",
            "h sshd[1]: Connection closed by 203.0.113.9 port 5 [preauth]",
            "h sshd[1]: Disconnected from user bob 203.0.113.9 port 5",
            "h CRON[5]: pam_unix(cron:session): session opened",
            "\u{0}\u{1b}[2J",
            "sshd: Failed password",
        ] {
            assert_eq!(parse(line), None, "{line:?}");
        }
    }

    #[test]
    fn hostile_text_is_cleaned_and_bad_addresses_become_null() {
        let line = format!(
            "h sshd[1]: Failed password for invalid user {}\u{202e}x from <script> port 1 ssh2",
            "u".repeat(200)
        );
        let (user, address, _, _) = fields(&line);
        assert_eq!(user.unwrap().chars().count(), text::MAX_USER_CHARS);
        assert_eq!(address, None);
        let nasty =
            parse("h sshd[1]: Failed password for root\u{1b}[31m from 999.1.1.1 port 1 ssh2");
        assert!(matches!(nasty, Some(Parsed::Failed { address: None, .. })));
    }
}
