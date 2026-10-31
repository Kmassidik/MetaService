//! The security reader on real files in a temp folder, grouping, and the route through the real axum router.
use super::commands::fake::FakeCommands;
use super::model::{Answer, EventType};
use super::{clock::Civil, Environment, Security};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;

/// 2026-11-01T00:00:00Z
pub(super) const NOW: i64 = 1_793_491_200;
pub(super) const DAY: i64 = 86_400;

pub(super) fn now() -> i64 {
    NOW
}

pub(super) fn plus_seven(civil: &Civil) -> Option<i64> {
    Some(civil.as_utc() - 7 * 3600)
}

pub(super) struct Rig {
    pub(super) root: PathBuf,
    pub(super) env: Environment,
}

impl Drop for Rig {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

impl Rig {
    pub(super) fn new() -> Rig {
        let root = std::env::temp_dir().join(format!("ms-security-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("var/log")).unwrap();
        let env = Environment {
            root: root.clone(),
            home: root.clone(),
            user: "u".into(),
            auth_log: root.join("var/log/auth.log"),
            fail2ban_log: root.join("var/log/fail2ban.log"),
        };
        Rig { root, env }
    }

    pub(super) fn security(&self) -> Security {
        self.security_with(FakeCommands::default())
    }

    fn security_with(&self, commands: FakeCommands) -> Security {
        Security::new(self.env.clone(), Arc::new(commands), now, plus_seven)
    }

    pub(super) fn auth(&self) -> PathBuf {
        self.env.auth_log.clone()
    }

    pub(super) fn fail2ban(&self) -> PathBuf {
        self.env.fail2ban_log.clone()
    }
}

pub(super) fn append(path: &PathBuf, text: &str) {
    OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .unwrap()
        .write_all(text.as_bytes())
        .unwrap();
}

/// A failed password line `minutes` before NOW, in the ISO format of Ubuntu 24.04 (UTC).
pub(super) fn failed(minutes: i64, user: &str, address: &str, port: u16) -> String {
    format!(
        "{} host sshd[10]: Failed password for {user} from {address} port {port} ssh2\n",
        iso_line(NOW - minutes * 60)
    )
}

pub(super) fn iso_line(epoch: i64) -> String {
    crate::stats::iso8601(epoch as u64).replace('Z', ".123456+00:00")
}

pub(super) fn kinds(answer: &Answer) -> Vec<(EventType, Option<String>, Option<String>, u32)> {
    answer
        .events
        .iter()
        .map(|event| {
            (
                event.kind,
                event.user.clone(),
                event.address.clone(),
                event.count,
            )
        })
        .collect()
}

pub(super) fn some(text: &str) -> Option<String> {
    Some(text.to_string())
}

// ---- reading

#[test]
fn a_first_call_reads_both_formats_groups_failures_and_knows_the_ban_time() {
    let rig = Rig::new();
    let classic_time = "Oct 31 17:10:00"; // 00:10 local at +7 the same day: 17:10Z, before NOW
    append(&rig.auth(), &failed(30, "root", "203.0.113.9", 1));
    append(&rig.auth(), &failed(29, "root", "203.0.113.9", 2));
    append(&rig.auth(), &failed(28, "admin", "203.0.113.9", 3));
    append(&rig.auth(), &format!("{} host sshd[11]: Accepted publickey for kurnia from 2001:db8::7 port 50 ssh2: ED25519 SHA256:x\n", iso_line(NOW - 600)));
    append(&rig.auth(), &format!("{classic_time} host sshd[12]: Accepted password for bob from 198.51.100.4 port 51 ssh2\n"));
    append(&rig.auth(), "garbage that is not a log line\n");
    append(&rig.fail2ban(), "2026-10-31 23:50:00,123 fail2ban.actions        [812]: NOTICE  [sshd] Ban 203.0.113.9\n2026-10-31 23:55:00,000 fail2ban.filter [812]: INFO [sshd] Found 203.0.113.9 - x\n");
    append(
        &rig.fail2ban(),
        "2026-10-31 23:59:00,000 fail2ban.actions [812]: NOTICE [sshd] Unban 203.0.113.9\n",
    );
    std::fs::create_dir_all(rig.root.join("etc/fail2ban")).unwrap();
    std::fs::write(
        rig.root.join("etc/fail2ban/jail.local"),
        "[sshd]\nbantime = 1h\n",
    )
    .unwrap();
    let answer = rig.security().events(None, 500);
    assert!(!answer.reset);
    let wanted = vec![
        (EventType::Login, some("bob"), some("198.51.100.4"), 1),
        (
            EventType::FailedLogin,
            some("admin"),
            some("203.0.113.9"),
            1,
        ),
        (EventType::FailedLogin, some("root"), some("203.0.113.9"), 2),
        (EventType::Login, some("kurnia"), some("2001:db8::7"), 1),
    ];
    let login_and_failures: Vec<_> = kinds(&answer)
        .into_iter()
        .filter(|(kind, ..)| matches!(kind, EventType::Login | EventType::FailedLogin))
        .collect();
    assert_eq!(login_and_failures.len(), wanted.len());
    for event in &wanted {
        assert!(
            login_and_failures.contains(event),
            "{event:?} in {login_and_failures:?}"
        );
    }
    let ban = answer
        .events
        .iter()
        .find(|event| event.kind == EventType::Blocked)
        .unwrap();
    assert_eq!(
        (ban.address.clone(), ban.time.as_str(), ban.until.as_deref()),
        (
            some("203.0.113.9"),
            "2026-10-31T16:50:00Z",
            Some("2026-10-31T17:50:00Z")
        )
    );
    let unban = answer
        .events
        .iter()
        .find(|event| event.kind == EventType::Unblocked)
        .unwrap();
    assert_eq!(unban.until, None);
    let times: Vec<&str> = answer
        .events
        .iter()
        .map(|event| event.time.as_str())
        .collect();
    assert!(
        times.windows(2).all(|pair| pair[0] <= pair[1]),
        "oldest first: {times:?}"
    );
    assert!(answer.events.iter().all(|event| event.count >= 1));
}

#[test]
fn a_cursor_resumes_with_only_what_is_new_and_an_idle_call_is_empty() {
    let rig = Rig::new();
    let security = rig.security();
    append(&rig.auth(), &failed(30, "root", "203.0.113.1", 1));
    let first = security.events(None, 500);
    assert_eq!(first.events.len(), 1);
    let idle = security.events(Some(&first.cursor), 500);
    assert_eq!(
        (idle.events.len(), idle.reset, idle.cursor.clone()),
        (0, false, first.cursor.clone())
    );
    append(&rig.auth(), &failed(10, "root", "203.0.113.2", 2));
    append(&rig.auth(), "2026-11-01T00:00:0"); // a line still being written is left for next time
    let second = security.events(Some(&first.cursor), 500);
    assert_eq!(
        (kinds(&second), second.reset),
        (
            vec![(EventType::FailedLogin, some("root"), some("203.0.113.2"), 1)],
            false
        )
    );
    append(
        &rig.auth(),
        "0.000000+00:00 host sshd[1]: Failed password for root from 203.0.113.3 port 9 ssh2\n",
    );
    let third = security.events(Some(&second.cursor), 500);
    assert_eq!(
        kinds(&third),
        vec![(EventType::FailedLogin, some("root"), some("203.0.113.3"), 1)]
    );
}

#[test]
fn limit_pages_through_every_line_exactly_once() {
    let rig = Rig::new();
    let security = rig.security();
    for index in 0..7 {
        append(
            &rig.auth(),
            &failed(60 - index, "root", &format!("203.0.113.{}", index + 1), 22),
        );
        append(&rig.auth(), "noise line without a time\n");
    }
    let (mut cursor, mut seen) = (None::<String>, Vec::new());
    for _ in 0..10 {
        let page = security.events(cursor.as_deref(), 3);
        assert!(page.events.len() <= 3);
        seen.extend(page.events.iter().filter_map(|event| event.address.clone()));
        let done = page.events.is_empty();
        cursor = Some(page.cursor);
        if done {
            break;
        }
    }
    let wanted: Vec<String> = (1..=7).map(|index| format!("203.0.113.{index}")).collect();
    assert_eq!(seen, wanted);
}

#[test]
fn a_rotation_continues_through_the_old_file_without_a_reset() {
    let rig = Rig::new();
    let security = rig.security();
    append(&rig.auth(), &failed(50, "root", "203.0.113.1", 1));
    let first = security.events(None, 500);
    append(&rig.auth(), &failed(40, "root", "203.0.113.2", 2));
    std::fs::rename(rig.auth(), rig.root.join("var/log/auth.log.1")).unwrap();
    append(&rig.auth(), &failed(30, "root", "203.0.113.3", 3));
    let after = security.events(Some(&first.cursor), 500);
    let addresses: Vec<_> = after
        .events
        .iter()
        .map(|event| event.address.clone().unwrap())
        .collect();
    assert_eq!(
        (addresses, after.reset),
        (
            vec!["203.0.113.2".to_string(), "203.0.113.3".to_string()],
            false
        )
    );
}

#[test]
fn a_file_replaced_by_an_unknown_one_resets_and_starts_from_what_it_can_read() {
    let rig = Rig::new();
    let security = rig.security();
    append(&rig.auth(), &failed(50, "root", "203.0.113.1", 1));
    let first = security.events(None, 500);
    std::fs::rename(rig.auth(), rig.root.join("var/log/elsewhere")).unwrap();
    append(&rig.auth(), &failed(20, "root", "203.0.113.9", 9));
    let after = security.events(Some(&first.cursor), 500);
    assert!(after.reset);
    assert_eq!(
        kinds(&after),
        vec![(EventType::FailedLogin, some("root"), some("203.0.113.9"), 1)]
    );
}

#[test]
fn a_shrunk_file_resets() {
    let rig = Rig::new();
    let security = rig.security();
    append(&rig.auth(), &failed(50, "root", "203.0.113.1", 1));
    append(&rig.auth(), &failed(49, "root", "203.0.113.2", 1));
    let first = security.events(None, 500);
    std::fs::write(rig.auth(), failed(5, "root", "203.0.113.7", 1)).unwrap();
    let after = security.events(Some(&first.cursor), 500);
    assert!(after.reset);
    assert_eq!(after.events.len(), 1);
}

#[test]
fn a_garbled_cursor_is_a_reset_and_never_an_error() {
    let rig = Rig::new();
    let security = rig.security();
    append(&rig.auth(), &failed(5, "root", "203.0.113.1", 1));
    for bad in [
        "garbage",
        "v1.a-1-2-3",
        "v1.a--1-2-3.f-x",
        "v1.a-1-2-18446744073709551616.f-x",
        "../../etc/passwd",
        &"x".repeat(5000),
    ] {
        let answer = security.events(Some(bad), 500);
        assert!(answer.reset, "{bad}");
        assert_eq!(answer.events.len(), 1, "{bad}");
    }
    assert!(
        !security.events(Some(""), 500).reset,
        "an empty cursor is no cursor"
    );
}

#[test]
fn the_first_call_keeps_seven_days_and_a_big_file_is_bisected_not_scanned() {
    let rig = Rig::new();
    append(
        &rig.auth(),
        &failed(DAY / 60 * 8, "root", "203.0.113.50", 1),
    );
    append(
        &rig.auth(),
        &failed(DAY / 60 * 6, "root", "203.0.113.51", 1),
    );
    let small = rig.security().events(None, 500);
    assert_eq!(
        kinds(&small),
        vec![(
            EventType::FailedLogin,
            some("root"),
            some("203.0.113.51"),
            1
        )],
        "the line of eight days ago is dropped"
    );
    std::fs::remove_file(rig.auth()).unwrap();
    let old = failed(DAY / 60 * 9, "root", "203.0.113.60", 1);
    let chunk = old.repeat(1_000_000 / old.len());
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(rig.auth())
        .unwrap();
    for _ in 0..(super::reader::WHOLE_FILE_BYTES / chunk.len() as u64 + 2) {
        file.write_all(chunk.as_bytes()).unwrap();
    }
    drop(file);
    append(&rig.auth(), &failed(120, "root", "203.0.113.61", 1));
    append(&rig.auth(), &failed(60, "root", "203.0.113.62", 1));
    assert!(std::fs::metadata(rig.auth()).unwrap().len() > super::reader::WHOLE_FILE_BYTES);
    let started = std::time::Instant::now();
    let big = rig.security().events(None, 500);
    assert_eq!(
        big.events
            .iter()
            .map(|event| event.address.clone().unwrap())
            .collect::<Vec<_>>(),
        vec!["203.0.113.61", "203.0.113.62"]
    );
    assert!(
        started.elapsed() < std::time::Duration::from_secs(5),
        "{:?}",
        started.elapsed()
    );
}

// ---- the journal fallback

const JOURNAL_CALL: &str =
    "journalctl -u ssh -u sshd --no-pager -o short-iso --utc --since 2026-10-25 00:00:00";

#[test]
fn without_auth_log_the_journal_is_asked_and_its_cursor_continues_by_time() {
    let rig = Rig::new();
    let journal = String::from("-- Logs begin --\n2026-10-31T23:00:00+0000 host sshd[1]: Failed password for root from 203.0.113.5 port 4 ssh2\n2026-10-31T23:00:00+0000 host sshd[1]: Connection closed by authenticating user root 203.0.113.5 port 4 [preauth]\n");
    let commands = FakeCommands::default()
        .with(JOURNAL_CALL, Ok(&journal))
        .with(
            "journalctl -u ssh -u sshd --no-pager -o short-iso --utc --since 2026-10-31 23:00:01",
            Ok("-- No entries --\n"),
        );
    let security = rig.security_with(commands);
    let first = security.events(None, 500);
    assert_eq!(
        kinds(&first),
        vec![(EventType::FailedLogin, some("root"), some("203.0.113.5"), 1)]
    );
    assert!(first.cursor.starts_with("v1.a-j-"), "{}", first.cursor);
    let second = security.events(Some(&first.cursor), 500);
    assert_eq!((second.events.len(), second.reset), (0, false));
}

#[test]
fn an_unreadable_auth_log_and_no_journal_answer_empty_with_the_baseline_filled() {
    use std::os::unix::fs::PermissionsExt;
    let rig = Rig::new();
    append(&rig.auth(), &failed(5, "root", "203.0.113.1", 1));
    std::fs::set_permissions(rig.auth(), std::fs::Permissions::from_mode(0o000)).unwrap();
    if std::fs::File::open(rig.auth()).is_ok() {
        return; // running as root: the file cannot be made unreadable
    }
    std::fs::create_dir_all(rig.root.join("etc/ssh")).unwrap();
    std::fs::write(
        rig.root.join("etc/ssh/sshd_config"),
        "PasswordAuthentication no\n",
    )
    .unwrap();
    let answer = rig.security().events(None, 500);
    assert_eq!((answer.events.len(), answer.reset), (0, false));
    assert_eq!(answer.baseline.password_login, Some(false));
}
