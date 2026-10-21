//! The sampler against a fake /proc tree in a temporary folder.
use super::disks::Sizes;
use super::sampler::{Environment, Sampler, MAX_SAMPLE_AGE};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const SECRET: &str = "hunter2-super-secret";

struct Tree(PathBuf);

impl Tree {
    fn new() -> Tree {
        let tree = Tree(std::env::temp_dir().join(format!("ms-proc-{}", rand::random::<u64>())));
        tree.put("proc/uptime", "5000.25 100.0\n");
        tree.put("proc/loadavg", "0.50 1.00 1.50 1/100 7\n");
        tree.put("proc/meminfo", "MemTotal: 1000 kB\nMemFree: 100 kB\nCached: 300 kB\n");
        tree.put("proc/mounts", "/dev/sda1 / ext4 rw 0 0\ntmpfs /run tmpfs rw 0 0\n");
        tree.put("etc/passwd", "root:x:0:0:root:/root:/bin/sh\nkurnia:x:1000:1000::/home/kurnia:/bin/sh\n");
        tree.cpu(100, 900, 100, 900);
        tree.net(1000, 500);
        tree.process(10, "busy <img src=x onerror=alert(1)>", 1000, 100, 2048);
        tree
    }

    fn put(&self, relative: &str, text: &str) {
        let path = self.0.join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn cpu(&self, busy_all: u64, idle_all: u64, busy_core: u64, idle_core: u64) {
        self.put("proc/stat", &format!("cpu  {busy_all} 0 0 {idle_all} 0 0 0 0\ncpu0 {busy_core} 0 0 {idle_core} 0 0 0 0\n"));
    }

    fn net(&self, received: u64, sent: u64) {
        self.put("proc/net/dev", &format!("hdr\n lo: 5 0 0 0 0 0 0 0 5 0\neth0: {received} 0 0 0 0 0 0 0 {sent} 0\n"));
    }

    fn process(&self, pid: u32, name: &str, ticks: u64, uid: u32, rss_kb: u64) {
        self.put(&format!("proc/{pid}/stat"), &format!("{pid} ({name}) S 1 1 1 0 -1 0 0 0 0 0 {ticks} 0 0 0 20 0 1 0 1 1 1\n"));
        self.put(&format!("proc/{pid}/status"), &format!("Name:\tx\nUid:\t{uid}\t{uid}\nVmRSS:\t{rss_kb} kB\n"));
        self.put(&format!("proc/{pid}/cmdline"), &format!("/usr/bin/tool\0--password={SECRET}\0"));
        self.put(&format!("proc/{pid}/environ"), &format!("TOKEN={SECRET}\0"));
    }

    fn sampler(&self) -> Sampler {
        fn sizes(_: &Path) -> Option<Sizes> {
            Some(Sizes { total: 10_000, free: 4_000 })
        }
        Sampler::new(Environment { root: self.0.clone(), size_of: sizes, ticks_per_second: 100 })
    }
}

impl Drop for Tree {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn first_answer_is_measuring_with_nulls_not_zeros() {
    let tree = Tree::new();
    let stats = tree.sampler().take(Instant::now(), 0, true).unwrap();
    assert!(stats.measuring);
    assert!(stats.cpu.total_percent.is_none() && stats.cpu.cores_percent.is_none());
    assert!(stats.network.received_bytes_per_second.is_none() && stats.network.sent_bytes_per_second.is_none());
    assert!(stats.processes.iter().all(|p| p.cpu_percent.is_none()));
    assert_eq!((stats.uptime_seconds, stats.cpu.core_count, stats.memory.total_bytes), (5000, 1, 1000 * 1024));
    assert_eq!((stats.network.received_total_bytes, stats.cpu.load.one), (1000, Some(0.5)));
}

#[test]
fn second_answer_has_percentages_and_rates() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, true).unwrap();
    tree.cpu(200, 1700, 150, 1850);
    tree.net(3000, 1500);
    tree.process(10, "busy <img src=x onerror=alert(1)>", 1200, 100, 2048);
    let stats = sampler.take(start + Duration::from_secs(2), 1_782_000_000, true).unwrap();
    assert!(!stats.measuring);
    assert_eq!(stats.taken_at, "2026-06-21T00:00:00Z");
    assert_eq!(stats.cpu.total_percent, Some(11.1));
    assert_eq!(stats.cpu.cores_percent, Some(vec![5.0]));
    assert_eq!(stats.network.received_bytes_per_second, Some(1000.0));
    assert_eq!(stats.network.sent_bytes_per_second, Some(500.0));
    assert_eq!(stats.processes[0].cpu_percent, Some(100.0), "200 ticks in 2 s at 100 Hz is one full core");
}

#[test]
fn an_old_previous_sample_means_measuring_again() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, true).unwrap();
    assert!(sampler.take(start + MAX_SAMPLE_AGE + Duration::from_secs(1), 0, true).unwrap().measuring);
}

#[test]
fn a_network_counter_that_went_backwards_is_null() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, true).unwrap();
    tree.net(10, 9999);
    let stats = sampler.take(start + Duration::from_secs(1), 0, true).unwrap();
    assert!(stats.network.received_bytes_per_second.is_none());
    assert!(stats.network.sent_bytes_per_second.is_some());
}

#[test]
fn the_command_line_and_environment_never_appear_anywhere() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, true).unwrap();
    let stats = sampler.take(start + Duration::from_secs(1), 0, true).unwrap();
    let json = serde_json::to_string(&stats).unwrap();
    assert!(!json.contains(SECRET) && !json.contains("--password") && !json.contains("/usr/bin/tool"));
}

#[test]
fn hostile_names_are_data_and_users_come_from_passwd() {
    let tree = Tree::new();
    let stats = tree.sampler().take(Instant::now(), 0, true).unwrap();
    assert_eq!(stats.processes[0].name, "busy <img src=x onerror=alert(1)>");
    assert_eq!(stats.processes[0].user, "100", "no passwd entry: the number as text");
    tree.process(11, "worker", 5, 1000, 10);
    let stats = tree.sampler().take(Instant::now(), 0, true).unwrap();
    assert!(stats.processes.iter().any(|p| p.user == "kurnia"));
}

#[test]
fn only_real_disks_and_the_json_has_no_gpu_key() {
    let tree = Tree::new();
    let stats = tree.sampler().take(Instant::now(), 0, true).unwrap();
    assert_eq!(stats.disks.len(), 1);
    assert_eq!((stats.disks[0].used_bytes, stats.disks[0].free_bytes), (6_000, 4_000));
    let json: serde_json::Value = serde_json::to_value(&stats).unwrap();
    assert!(json.get("gpus").is_none());
    assert!(json["cpu"]["total_percent"].is_null());
}

#[test]
fn a_missing_stat_file_is_an_error_not_a_zero() {
    let tree = Tree::new();
    std::fs::remove_file(tree.0.join("proc/stat")).unwrap();
    assert!(tree.sampler().take(Instant::now(), 0, true).is_err());
}

#[test]
fn without_the_program_list_the_answer_has_none_and_the_machine_numbers_are_ready() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, false).unwrap();
    tree.cpu(200, 1700, 150, 1850);
    let stats = sampler.take(start + Duration::from_secs(2), 0, false).unwrap();
    assert!(stats.processes.is_empty());
    assert!(!stats.measuring);
    assert_eq!(stats.cpu.total_percent, Some(11.1));
}

#[test]
fn programs_after_an_answer_without_them_have_no_cpu_yet_not_a_false_zero() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, false).unwrap();
    tree.cpu(200, 1700, 150, 1850);
    tree.process(10, "busy", 1200, 100, 2048);
    let stats = sampler.take(start + Duration::from_secs(2), 0, true).unwrap();
    assert!(!stats.measuring, "the machine numbers are ready");
    assert_eq!(stats.processes.len(), 1);
    assert_eq!(stats.processes[0].cpu_percent, None);
}

#[test]
fn the_next_answer_with_programs_has_their_cpu() {
    let tree = Tree::new();
    let sampler = tree.sampler();
    let start = Instant::now();
    sampler.take(start, 0, false).unwrap();
    sampler.take(start + Duration::from_secs(2), 0, true).unwrap();
    tree.process(10, "busy", 1200, 100, 2048);
    let stats = sampler.take(start + Duration::from_secs(4), 0, true).unwrap();
    assert_eq!(stats.processes[0].cpu_percent, Some(100.0));
}
