//! The watchdog's rounds with a scripted `incus`, a scripted card and scripted `/proc` files.
use super::*;
use crate::models::EngineError;
use std::sync::Mutex;

/// A container limited to 1 GB (1024 MiB), a container without a limit, and a limited one that is stopped.
const LIST: &str = r#"[
 {"name":"ms-w-1","status":"Running","config":{"user.metaservice.id":"w-1","user.metaservice.name":"a","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1","user.metaservice.gpu_memory_gb":"1"}},
 {"name":"ms-w-2","status":"Running","config":{"user.metaservice.id":"w-2","user.metaservice.name":"b","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1"}},
 {"name":"ms-w-3","status":"Stopped","config":{"user.metaservice.id":"w-3","user.metaservice.name":"c","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1","user.metaservice.gpu_memory_gb":"1"}}
]"#;

struct ScriptedIncus {
    calls: Mutex<Vec<Vec<String>>>,
    polite_stop_fails: bool,
    every_stop_fails: bool,
}

impl ScriptedIncus {
    fn new(polite_stop_fails: bool, every_stop_fails: bool) -> Arc<Self> {
        Arc::new(ScriptedIncus { calls: Mutex::new(Vec::new()), polite_stop_fails, every_stop_fails })
    }

    fn calls(&self) -> Vec<Vec<String>> {
        self.calls.lock().unwrap().clone()
    }

    fn stops(&self) -> Vec<Vec<String>> {
        self.calls().into_iter().filter(|call| call[0] == "stop").collect()
    }
}

impl Runner for ScriptedIncus {
    fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push(arguments.to_vec());
        let polite = arguments.iter().any(|a| a == "--timeout");
        match arguments[0].as_str() {
            "list" => Ok(LIST.into()),
            "stop" if self.every_stop_fails || polite && self.polite_stop_fails => Err(EngineError::Failed("busy".into())),
            _ => Ok(String::new()),
        }
    }

    fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.run(arguments, timeout)
    }
}

/// Process 10 and 11 live in ms-w-1, process 20 in ms-w-2 (no limit), process 30 in no container.
fn proc_files(pid: u32) -> Option<String> {
    match pid {
        10 | 11 => Some("0::/lxc.payload.ms-w-1/system.slice/python.service\n".into()),
        20 => Some("0::/lxc.payload.ms-w-2/init.scope\n".into()),
        30 => Some("0::/user.slice/user-1000.slice/session-1.scope\n".into()),
        _ => None,
    }
}

fn watchdog(runner: Arc<ScriptedIncus>, card: Arc<Mutex<Option<Vec<PidMemory>>>>) -> Watchdog {
    Watchdog::new(runner, Box::new(move || card.lock().unwrap().clone()), Box::new(proc_files))
}

fn card(programs: &[(u32, u64)]) -> Arc<Mutex<Option<Vec<PidMemory>>>> {
    Arc::new(Mutex::new(Some(programs.iter().map(|(pid, used_mib)| PidMemory { pid: *pid, used_mib: *used_mib }).collect())))
}

fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

#[test]
fn three_over_rounds_stop_the_container_by_name_and_record_why() {
    let runner = ScriptedIncus::new(false, false);
    // Two programs of ms-w-1 add up to 1100 MiB, over its 1024.
    let mut watch = watchdog(runner.clone(), card(&[(10, 600), (11, 500), (20, 9000), (30, 9000)]));
    assert!(watch.round().is_empty() && watch.round().is_empty());
    assert!(runner.stops().is_empty());
    assert_eq!(watch.round(), ["ms-w-1"]);
    assert_eq!(runner.stops(), [strings(&["stop", "ms-w-1", "--timeout", "10"])]);
    let settings: Vec<Vec<String>> = runner.calls().into_iter().filter(|call| call[0] == "config").collect();
    assert_eq!(settings, [
        strings(&["config", "set", "ms-w-1", "user.metaservice.gpu_stop_code", "gpu_memory_over_limit"]),
        strings(&["config", "set", "ms-w-1", "user.metaservice.gpu_stop_used_mib", "1100"]),
    ]);
}

#[test]
fn a_polite_stop_that_fails_is_followed_by_a_forced_one() {
    let runner = ScriptedIncus::new(true, false);
    let mut watch = watchdog(runner.clone(), card(&[(10, 2000)]));
    for _ in 0..3 { watch.round(); }
    assert_eq!(runner.stops(), [strings(&["stop", "ms-w-1", "--timeout", "10"]), strings(&["stop", "ms-w-1", "--force"])]);
}

#[test]
fn a_stop_that_fails_both_ways_records_nothing_and_is_asked_again_later() {
    let runner = ScriptedIncus::new(true, true);
    let mut watch = watchdog(runner.clone(), card(&[(10, 2000)]));
    for _ in 0..3 { assert!(watch.round().is_empty()); }
    assert!(!runner.calls().iter().any(|call| call[0] == "config"));
    for _ in 0..3 { watch.round(); }
    assert_eq!(runner.stops().len(), 4, "two tries for each of the two episodes");
}

#[test]
fn nothing_is_stopped_while_the_container_stays_within_its_limit_or_the_card_cannot_be_read() {
    let runner = ScriptedIncus::new(false, false);
    let programs = card(&[(10, 1024), (20, 9000), (30, 9000)]);
    let mut watch = watchdog(runner.clone(), programs.clone());
    for _ in 0..6 { assert!(watch.round().is_empty()); }
    *programs.lock().unwrap() = None;
    for _ in 0..6 { assert!(watch.round().is_empty()); }
    assert!(runner.stops().is_empty());
}

#[test]
fn a_stopped_container_with_a_limit_is_not_watched() {
    let runner = ScriptedIncus::new(false, false);
    let mut watch = watchdog(runner.clone(), Arc::new(Mutex::new(Some(vec![PidMemory { pid: 99, used_mib: 99999 }]))));
    for _ in 0..5 { assert!(watch.round().is_empty()); }
    assert!(runner.stops().is_empty());
}
