//! The process list from /proc/<pid>/stat and /proc/<pid>/status: program name, user, CPU ticks and resident memory.
//! The command line (/proc/<pid>/cmdline), the environment and open files are never opened.
use super::model::{cut, one_decimal, Process, MAX_NAME_CHARS, MAX_PROCESSES};
use std::collections::HashMap;
use std::path::Path;

const BYTES_PER_KB: u64 = 1024;
/// After the closing bracket of the name: state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime.
const USER_TIME_FIELD: usize = 11;
const SYSTEM_TIME_FIELD: usize = 12;

/// What one process looked like at one moment.
#[derive(Debug, Clone, PartialEq)]
pub struct Seen {
    pub pid: u32,
    pub name: String,
    pub uid: Option<u32>,
    pub cpu_ticks: u64,
    pub memory_bytes: u64,
    pub threads: Option<u32>,
}

/// What /proc/<pid>/status says: the real user number, resident memory (0 for a kernel thread) and the thread count.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Status {
    pub uid: Option<u32>,
    pub memory_bytes: u64,
    pub threads: Option<u32>,
}

/// pid to CPU ticks, kept from the earlier sample.
pub type Earlier = HashMap<u32, u64>;

pub fn scan(proc_dir: &Path) -> Vec<Seen> {
    let Ok(entries) = std::fs::read_dir(proc_dir) else { return Vec::new() };
    entries.flatten().filter_map(|entry| {
        let pid: u32 = entry.file_name().to_str()?.parse().ok()?;
        let stat = std::fs::read_to_string(entry.path().join("stat")).ok()?;
        let (name, cpu_ticks) = parse_stat(&stat)?;
        let status = std::fs::read_to_string(entry.path().join("status")).map(|s| parse_status(&s)).unwrap_or_default();
        Some(Seen { pid, name, uid: status.uid, cpu_ticks, memory_bytes: status.memory_bytes, threads: status.threads })
    }).collect()
}

/// `pid (name) S ...`: the name may hold spaces and brackets, so it ends at the LAST closing bracket.
pub fn parse_stat(text: &str) -> Option<(String, u64)> {
    let open = text.find('(')?;
    let close = text.rfind(')')?;
    let after: Vec<&str> = text.get(close + 1..)?.split_whitespace().collect();
    let user: u64 = after.get(USER_TIME_FIELD)?.parse().ok()?;
    let system: u64 = after.get(SYSTEM_TIME_FIELD)?.parse().ok()?;
    Some((text.get(open + 1..close)?.to_string(), user.saturating_add(system)))
}

pub fn parse_status(text: &str) -> Status {
    let mut status = Status::default();
    for line in text.lines() {
        let Some((key, rest)) = line.split_once(':') else { continue };
        let first = rest.split_whitespace().next();
        match key {
            "Uid" => status.uid = first.and_then(|n| n.parse().ok()),
            "VmRSS" => status.memory_bytes = first.and_then(|n| n.parse::<u64>().ok()).unwrap_or(0) * BYTES_PER_KB,
            "Threads" => status.threads = first.and_then(|n| n.parse().ok()),
            _ => {}
        }
    }
    status
}

/// uid to user name from an /etc/passwd text.
pub fn parse_passwd(text: &str) -> HashMap<u32, String> {
    text.lines().filter_map(|line| {
        let mut fields = line.split(':');
        let name = fields.next()?;
        let uid = fields.nth(1)?.parse().ok()?;
        Some((uid, name.to_string()))
    }).collect()
}

/// The top processes: highest CPU first (memory first while CPU is unknown), at most 15, names cut at 64 characters.
pub fn top(seen: Vec<Seen>, earlier: Option<&Earlier>, seconds: f64, ticks_per_second: f64, users: &HashMap<u32, String>) -> Vec<Process> {
    let mut all: Vec<Process> = seen.into_iter().map(|p| Process {
        pid: p.pid,
        user: cut(&user_name(p.uid, users), MAX_NAME_CHARS),
        cpu_percent: earlier.map(|before| cpu_percent(before.get(&p.pid).copied(), p.cpu_ticks, seconds, ticks_per_second)),
        name: cut(&p.name, MAX_NAME_CHARS),
        memory_bytes: p.memory_bytes,
        threads: p.threads,
    }).collect();
    all.sort_by(|a, b| b.cpu_percent.unwrap_or(0.0).total_cmp(&a.cpu_percent.unwrap_or(0.0)).then(b.memory_bytes.cmp(&a.memory_bytes)).then(a.pid.cmp(&b.pid)));
    all.truncate(MAX_PROCESSES);
    all
}

/// Percent of ONE core. A process we did not see before, or one whose counter went back (a reused number), counts as 0.
fn cpu_percent(before: Option<u64>, now: u64, seconds: f64, ticks_per_second: f64) -> f64 {
    let gained = before.and_then(|b| now.checked_sub(b)).unwrap_or(0);
    one_decimal(gained as f64 / ticks_per_second / seconds * 100.0)
}

fn user_name(uid: Option<u32>, users: &HashMap<u32, String>) -> String {
    let Some(uid) = uid else { return String::new() };
    users.get(&uid).cloned().unwrap_or_else(|| uid.to_string())
}

pub fn ticks_of(seen: &[Seen]) -> Earlier {
    seen.iter().map(|p| (p.pid, p.cpu_ticks)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seen(pid: u32, ticks: u64, memory: u64) -> Seen {
        Seen { pid, name: format!("p{pid}"), uid: Some(0), cpu_ticks: ticks, memory_bytes: memory, threads: None }
    }

    #[test]
    fn name_with_spaces_and_brackets_is_read_whole() {
        let line = "42 (my (odd) name) S 1 1 1 0 -1 4194304 10 0 0 0 7 5 0 0 20 0 1 0 100 1000 10 18446744073709551615";
        assert_eq!(parse_stat(line), Some(("my (odd) name".to_string(), 12)));
        assert!(parse_stat("garbage").is_none());
    }

    #[test]
    fn status_gives_user_number_and_resident_memory() {
        let status = parse_status("Name:\tx\nUid:\t1000\t1000\t1000\t1000\nVmRSS:\t   2048 kB\nThreads:\t12\n");
        assert_eq!(status, Status { uid: Some(1000), memory_bytes: 2048 * 1024, threads: Some(12) });
        assert_eq!(parse_status("Name:\tkthreadd\nUid:\t0\t0\t0\t0\n"), Status { uid: Some(0), memory_bytes: 0, threads: None });
    }

    #[test]
    fn passwd_maps_numbers_to_names() {
        let users = parse_passwd("root:x:0:0:root:/root:/bin/bash\nkurnia:x:1000:1000::/home/kurnia:/bin/zsh\nbad\n");
        assert_eq!((users[&0].as_str(), users[&1000].as_str()), ("root", "kurnia"));
    }

    #[test]
    fn busiest_first_then_memory_then_pid_and_at_most_fifteen() {
        let earlier: Earlier = (1..=20).map(|pid| (pid, 0)).collect();
        let mut list: Vec<Seen> = (1..=20).map(|pid| seen(pid, 100, 10)).collect();
        list[4].cpu_ticks = 400;
        list[9].memory_bytes = 99;
        let top = top(list, Some(&earlier), 1.0, 100.0, &HashMap::new());
        assert_eq!(top.len(), MAX_PROCESSES);
        assert_eq!((top[0].pid, top[0].cpu_percent), (5, Some(400.0)));
        assert_eq!(top[1].pid, 10, "same CPU, more memory");
        assert_eq!(top[2].pid, 1, "same everything, lowest pid");
    }

    #[test]
    fn while_measuring_cpu_is_null_and_memory_decides() {
        let top = top(vec![seen(1, 5, 10), seen(2, 5, 50)], None, 1.0, 100.0, &HashMap::new());
        assert_eq!((top[0].pid, top[0].cpu_percent), (2, None));
    }

    #[test]
    fn new_and_reused_pids_count_as_zero() {
        let earlier: Earlier = [(1, 1000)].into();
        let top = top(vec![seen(1, 10, 1), seen(2, 10, 2)], Some(&earlier), 1.0, 100.0, &HashMap::new());
        assert!(top.iter().all(|p| p.cpu_percent == Some(0.0)));
    }

    #[test]
    fn names_and_users_are_cut_by_characters_and_unknown_users_show_their_number() {
        let mut long = seen(1, 0, 0);
        long.name = "é".repeat(100);
        long.uid = Some(4242);
        let top = top(vec![long], None, 1.0, 100.0, &HashMap::new());
        assert_eq!(top[0].name.chars().count(), MAX_NAME_CHARS);
        assert_eq!(top[0].user, "4242");
    }
}
