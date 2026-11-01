use super::host::{Host, Reply};
use super::*;
use std::cell::RefCell;

const START: &str = "#!/bin/sh\nnohup ./bin/metaservice-agent run --state-dir state --engine incus --port 9101 --bind 127.0.0.1 --chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5 >> logs/agent.log 2>&1 &\n";

#[derive(Default)]
struct FakeHost {
    calls: RefCell<Vec<String>>,
    linger: bool,
    alive_pids: Vec<u32>,
    active: bool,
    enabled: RefCell<bool>,
    failing: Option<&'static str>,
}

impl Host for FakeHost {
    fn systemctl(&self, arguments: &[&str]) -> Result<Reply, String> {
        let call = arguments.join(" ");
        self.calls.borrow_mut().push(call.clone());
        if self.failing.is_some_and(|word| call.starts_with(word)) {
            return Ok(Reply { success: false, text: "Failed to connect to bus".into() });
        }
        let success = match arguments[0] {
            "enable" => { *self.enabled.borrow_mut() = true; true }
            "disable" => { *self.enabled.borrow_mut() = false; true }
            "is-enabled" => *self.enabled.borrow(),
            "is-active" => self.active,
            _ => true,
        };
        Ok(Reply { success, text: String::new() })
    }
    fn linger(&self, _user: &str) -> Result<bool, String> { Ok(self.linger) }
    fn process_alive(&self, pid: u32) -> bool { self.alive_pids.contains(&pid) }
}

struct Machine {
    root: PathBuf,
}

impl Machine {
    fn new() -> Machine {
        let root = std::env::temp_dir().join(format!("ms-autostart-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("box/state")).unwrap();
        std::fs::write(root.join("box/start.sh"), START).unwrap();
        Machine { root }
    }
    fn with<'a>(&self, host: &'a FakeHost) -> Autostart<'a> {
        Autostart { home: self.root.join("home"), box_dir: self.root.join("box"), user: "kurnia".into(), host }
    }
    fn unit(&self) -> PathBuf { self.root.join("home/.config/systemd/user/metaservice-agent.service") }
    fn pid(&self, pid: u32) { std::fs::write(self.root.join("box/state/agent.pid"), format!("{pid}\n")).unwrap(); }
}

fn host(linger: bool) -> FakeHost { FakeHost { linger, ..FakeHost::default() } }

#[test]
fn on_writes_the_unit_enables_it_and_starts_when_nothing_runs() {
    let machine = Machine::new();
    let fake = host(true);
    let outcome = machine.with(&fake).on().unwrap();
    assert_eq!(outcome.code, EXIT_EFFECTIVE);
    let text = std::fs::read_to_string(machine.unit()).unwrap();
    assert!(text.contains(&format!("ExecStart={}/box/bin/metaservice-agent run --state-dir state --engine incus", machine.root.display())), "{text}");
    assert!(text.contains(&format!("WorkingDirectory={}/box\n", machine.root.display())));
    assert_eq!(*fake.calls.borrow(), ["daemon-reload", "enable metaservice-agent.service", "is-active metaservice-agent.service", "start metaservice-agent.service"]);
}

#[test]
fn on_does_not_start_a_second_copy_beside_the_helper_of_start_sh() {
    let machine = Machine::new();
    machine.pid(4242);
    let fake = FakeHost { linger: true, alive_pids: vec![4242], ..FakeHost::default() };
    let outcome = machine.with(&fake).on().unwrap();
    assert_eq!(outcome.code, EXIT_EFFECTIVE);
    assert!(!fake.calls.borrow().iter().any(|call| call.starts_with("start")), "{:?}", fake.calls);
    assert!(outcome.lines.iter().any(|line| line.contains("already running")));
}

#[test]
fn a_stale_pid_file_does_not_count_as_a_running_helper() {
    let machine = Machine::new();
    machine.pid(4242);
    let fake = host(true);
    machine.with(&fake).on().unwrap();
    assert!(fake.calls.borrow().iter().any(|call| call.starts_with("start ")));
}

#[test]
fn on_twice_changes_nothing_the_second_time() {
    let machine = Machine::new();
    let fake = FakeHost { linger: true, active: true, ..FakeHost::default() };
    machine.with(&fake).on().unwrap();
    let first = std::fs::metadata(machine.unit()).unwrap().modified().unwrap();
    let again = machine.with(&fake).on().unwrap();
    assert_eq!(again.code, EXIT_EFFECTIVE);
    assert_eq!(std::fs::metadata(machine.unit()).unwrap().modified().unwrap(), first);
    assert!(again.lines[0].contains("already in place"));
    assert!(!fake.calls.borrow().iter().any(|call| call.starts_with("start ")), "a running unit is not started again");
}

#[test]
fn without_linger_on_still_enables_and_exits_with_three_and_one_sudo_line() {
    let machine = Machine::new();
    let fake = host(false);
    let outcome = machine.with(&fake).on().unwrap();
    assert_eq!(outcome.code, EXIT_NEEDS_SUDO);
    assert!(machine.unit().is_file());
    assert!(fake.calls.borrow().contains(&"enable metaservice-agent.service".to_string()));
    let sudo: Vec<_> = outcome.lines.iter().filter(|line| line.contains("sudo")).collect();
    assert_eq!(sudo.len(), 1);
    assert!(sudo[0].contains("sudo loginctl enable-linger kurnia"));
}

#[test]
fn on_fails_plainly_when_systemd_refuses_or_start_sh_is_missing() {
    let machine = Machine::new();
    let fake = FakeHost { failing: Some("enable"), ..host(true) };
    let error = machine.with(&fake).on().unwrap_err();
    assert!(error.contains("systemctl --user enable") && error.contains("Failed to connect to bus"), "{error}");
    std::fs::remove_file(machine.root.join("box/start.sh")).unwrap();
    assert!(machine.with(&host(true)).on().unwrap_err().contains("start.sh"));
}

#[test]
fn status_is_one_json_line_and_effective_needs_all_three() {
    let machine = Machine::new();
    let line = |fake: &FakeHost| -> serde_json::Value { serde_json::from_str(&machine.with(fake).status().lines[0]).unwrap() };
    let before = line(&host(true));
    assert_eq!(before, json!({"unit_written": false, "enabled": false, "linger": true, "running_by_systemd": false, "effective": false}));
    let fake = FakeHost { active: true, ..host(true) };
    machine.with(&fake).on().unwrap();
    let after = line(&fake);
    assert_eq!(after["effective"], true);
    assert_eq!(after["running_by_systemd"], true);
    let no_linger = FakeHost { linger: false, active: true, enabled: RefCell::new(true), ..FakeHost::default() };
    assert_eq!(line(&no_linger)["effective"], false);
}

#[test]
fn status_changes_nothing() {
    let machine = Machine::new();
    let fake = host(true);
    machine.with(&fake).status();
    assert!(!machine.unit().exists());
    assert!(fake.calls.borrow().iter().all(|call| call.starts_with("is-")));
}

#[test]
fn off_disables_removes_the_unit_and_leaves_the_helper_running() {
    let machine = Machine::new();
    let fake = host(true);
    machine.with(&fake).on().unwrap();
    fake.calls.borrow_mut().clear();
    let outcome = machine.with(&fake).off().unwrap();
    assert_eq!(outcome.code, EXIT_EFFECTIVE);
    assert!(!machine.unit().exists());
    assert_eq!(*fake.calls.borrow(), ["disable metaservice-agent.service", "daemon-reload"]);
    let again = machine.with(&fake).off().unwrap();
    assert_eq!(again.code, EXIT_EFFECTIVE, "off twice is fine");
}

#[test]
fn the_arguments_are_checked() {
    let words = |items: &[&str]| items.iter().map(|s| s.to_string()).collect::<Vec<_>>();
    assert!(parse(&words(&[])).is_err());
    assert!(parse(&words(&["sideways"])).is_err());
    assert!(parse(&words(&["on", "--box"])).is_err());
    assert!(parse(&words(&["on", "--other", "x"])).is_err());
    let (action, box_dir) = parse(&words(&["status", "--box", "/b"])).unwrap();
    assert_eq!((action, box_dir), (Action::Status, PathBuf::from("/b")));
}
