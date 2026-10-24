//! The runner's request list, its wire format and its cleanup, without root, without iptables and without Firecracker: the machine behind it is a host
//! that records what it was asked. The one thing exercised for real is the socket, because the wire format is the contract between the helper and root.
use super::api::Api;
use super::host::Host;
use super::layout::{Files, Layout};
use super::protocol::{Reply, Request, PROTOCOL};
use super::tests_api::FakeApi;
use super::{Runner, RunnerClient, Server, Settings};
use crate::sandbox::firecracker::{Step, SLOTS};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

pub(super) const ID: &str = "abcdefghij0123456789";
const OTHER: &str = "zyxwvutsrq9876543210";

/// The machine, recording instead of doing. `failing` names one program that fails, so a half-done create can be looked at.
#[derive(Default)]
pub(super) struct FakeHost {
    ran: Mutex<Vec<String>>,
    spawned: Mutex<Vec<String>>,
    stopped: Mutex<Vec<String>>,
    failing: Option<&'static str>,
}

impl FakeHost {
    pub(super) fn failing(program: &'static str) -> Arc<FakeHost> {
        Arc::new(FakeHost { failing: Some(program), ..FakeHost::default() })
    }

    fn ran(&self) -> Vec<String> {
        self.ran.lock().unwrap().clone()
    }

    /// Whether a stop reached it, for the tests that care about the process and not the files.
    pub(super) fn stopped_now(&self) -> bool {
        !self.stopped.lock().unwrap().is_empty()
    }
}

impl Host for FakeHost {
    fn run(&self, step: &Step) -> Result<(), String> {
        self.ran.lock().unwrap().push(step.describe());
        match self.failing {
            Some(program) if step.program == program => Err(format!("{program} refused it")),
            _ => Ok(()),
        }
    }

    fn spawn(&self, files: &Files, step: &Step) -> Result<(), String> {
        self.spawned.lock().unwrap().push(format!("{} (pid kept in {})", step.describe(), files.pid.display()));
        Ok(())
    }

    fn stop(&self, files: &Files) -> Result<(), String> {
        self.stopped.lock().unwrap().push(files.pid.display().to_string());
        Ok(())
    }
}

/// A scratch directory with the pinned kernel and base disk in it, and a run directory beside them.
pub(super) struct Scratch {
    root: PathBuf,
}

impl Scratch {
    pub(super) fn new(name: &str) -> Scratch {
        let root = std::env::temp_dir().join(format!("ms-runner-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("vmlinux"), "kernel").unwrap();
        std::fs::write(root.join("rootfs.ext4"), "disk").unwrap();
        Scratch { root }
    }

    fn settings(&self) -> Settings {
        Settings { socket: self.root.join("runner.sock"), run_dir: self.root.join("run"), uplink: "eth0".into(), kernel: self.root.join("vmlinux"), rootfs: self.root.join("rootfs.ext4") }
    }

    pub(super) fn server(&self, host: Arc<FakeHost>) -> Server {
        Server::with_host(self.settings(), host).unwrap()
    }

    pub(super) fn server_with_api(&self, host: Arc<FakeHost>, api: Arc<dyn Api>) -> Server {
        Server::with_host_and_api(self.settings(), host, api).unwrap()
    }

    /// The run directory, which is where a sandbox's own files are.
    pub(super) fn run_dir(&self) -> PathBuf {
        self.root.join("run")
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

pub(super) fn create(id: &str) -> Request {
    Request::CreateNetwork { id: id.into(), internet: true }
}

pub(super) fn start(id: &str) -> Request {
    Request::Start { id: id.into(), vcpu: 2, ram_mb: 512 }
}

#[test]
fn health_says_which_protocol_the_runner_speaks() {
    let scratch = Scratch::new("health");
    let host = Arc::new(FakeHost::default());
    assert_eq!(scratch.server(host.clone()).answer(Request::Health), Reply::Health { version: crate::config::VERSION.into(), protocol: PROTOCOL });
    assert!(host.ran().is_empty(), "asking the runner about itself touches nothing");
}

#[test]
fn a_created_network_is_the_namespace_the_pair_and_the_rules_in_that_order() {
    let scratch = Scratch::new("create");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    assert_eq!(server.answer(create(ID)), Reply::Done { slot: Some(0), steps: 27 });
    let ran = host.ran();
    assert_eq!(ran[0], "ip netns add ms0");
    assert_eq!(ran[12], "ip netns exec ms0 ip route add default via 10.64.0.2");
    assert_eq!(ran[13], "iptables -w 5 -A FORWARD -i ms0h -d 10.0.0.0/8 -j DROP", "the rules come after the namespace they close");
    assert_eq!(ran.len(), 27, "thirteen steps for the namespace, then fourteen rules for what it may not reach");
    let layout = Layout::new(scratch.root.join("run"));
    assert_eq!(layout.read_slot(&layout.files(ID).ok().unwrap()), Some((0, true)), "the slot and the internet flag are kept for the delete");
    assert_eq!(server.answer(create(ID)), Reply::Done { slot: Some(0), steps: 0 }, "a retried create changes nothing");
    assert_eq!(host.ran().len(), 27);
}

#[test]
fn firecracker_starts_only_from_a_network_that_is_there() {
    let scratch = Scratch::new("start");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    assert!(server.answer(start(ID)).is_failed(), "a sandbox with no network is refused, not started unreachable");
    assert!(server.answer(create(ID)).is_done());
    assert!(server.answer(start(ID)).is_done());
    let spawned = host.spawned.lock().unwrap().clone();
    assert_eq!(spawned.len(), 1);
    assert!(spawned[0].starts_with(&format!("/usr/local/bin/jailer --id {ID} --exec-file /usr/local/bin/firecracker --uid 30000 --gid 30000")), "{}", spawned[0]);
    assert!(spawned[0].contains("--netns ms0"), "{}", spawned[0]);
    assert!(spawned[0].contains("--chroot-dir ") && spawned[0].contains("-- --api-sock /firecracker.sock --config-file /config.json"), "{}", spawned[0]);
    assert!(!spawned[0].contains("--no-api"), "a boot with no API cannot be paused or snapshotted: {}", spawned[0]);
    assert!(!spawned[0].contains("--daemonize"), "the runner keeps the pid it started, so a stop can find it");
    let jail = scratch.root.join(format!("run/jail/{ID}/root"));
    let config: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(jail.join("config.json")).unwrap()).unwrap();
    assert_eq!(config["machine-config"], serde_json::json!({"vcpu_count": 2, "mem_size_mib": 512, "smt": false}));
    assert_eq!(config["network-interfaces"][0]["host_dev_name"], "tap0");
    assert_eq!(config["vsock"]["guest_cid"], 3, "the first sandbox gets the first vsock id");
    assert!(jail.join("vmlinux").is_file(), "the jail holds the kernel the config names");
    let files = Layout::new(scratch.root.join("run")).files(ID).ok().unwrap();
    assert_eq!(files.disk, jail.join("rootfs.ext4"), "and the disk the config names is the sandbox's own copy, made by the copy step");
}

#[test]
fn a_delete_takes_the_rules_the_namespace_and_the_jail_out_and_frees_the_slot() {
    let scratch = Scratch::new("delete");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    server.answer(create(ID));
    let created = host.ran();
    assert!(server.answer(Request::DeleteNetwork { id: ID.into() }).is_done());
    let ran = host.ran();
    assert_eq!(ran[created.len()], "ip link del dev ms0h");
    assert_eq!(ran[created.len() + 1], "ip netns del ms0");
    assert!(ran.iter().any(|step| step.contains("-D FORWARD")), "the rules go back out");
    assert!(ran.iter().any(|step| step.contains("-t nat -D POSTROUTING")), "and the way out with them");
    assert!(!scratch.root.join(format!("run/jail/{ID}")).exists(), "the jail is gone");
    assert!(server.answer(create(OTHER)).is_done(), "the slot is free again");
    assert!(server.answer(Request::DeleteNetwork { id: ID.into() }).is_done(), "a delete of a sandbox that is gone changes nothing");
}

#[test]
fn a_create_that_fails_half_way_leaves_nothing_behind() {
    let scratch = Scratch::new("rollback");
    let host = FakeHost::failing("iptables");
    let server = scratch.server(host.clone());
    assert!(server.answer(create(ID)).is_failed());
    let ran = host.ran();
    assert!(ran.iter().any(|step| step == "ip netns del ms0"), "what was made is taken back: {ran:?}");
    assert!(!scratch.root.join(format!("run/jail/{ID}")).exists());
    assert!(server.answer(start(ID)).is_failed(), "the slot went back with the namespace");
}

#[test]
fn a_stop_only_stops_the_process_and_the_network_stays_until_its_delete() {
    let scratch = Scratch::new("stop");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    server.answer(create(ID));
    assert_eq!(server.answer(Request::Stop { id: ID.into() }), Reply::Done { slot: Some(0), steps: 1 });
    assert_eq!(host.stopped.lock().unwrap().len(), 1);
    assert!(!host.ran().iter().any(|step| step.starts_with("ip netns del")), "a stop is not a delete");
}

#[test]
fn a_start_gives_the_sandbox_its_own_disk_before_firecracker_runs() {
    let scratch = Scratch::new("disk");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    server.answer(create(ID));
    assert!(server.answer(start(ID)).is_done());
    let files = Layout::new(scratch.root.join("run")).files(ID).ok().unwrap();
    let ran = host.ran();
    let last = ran.last().unwrap();
    assert_eq!(
        last,
        &format!("/bin/cp --reflink=auto -- {} {}", scratch.root.join("rootfs.ext4").display(), files.disk.display()),
        "one copy, into the sandbox's own jail, before the jailer runs"
    );
    assert_eq!(files.disk, scratch.root.join(format!("run/jail/{ID}/root/rootfs.ext4")));
}

#[test]
fn a_disk_copy_that_fails_starts_nothing_and_leaves_the_template_alone() {
    let scratch = Scratch::new("nocopy");
    let host = FakeHost::failing("/bin/cp");
    let server = scratch.server(host.clone());
    server.answer(create(ID));
    assert!(server.answer(start(ID)).is_failed(), "a sandbox with no disk of its own is not started on the template's");
    let files = Layout::new(scratch.root.join("run")).files(ID).ok().unwrap();
    assert!(!files.disk.exists(), "the half copy is taken away");
    assert_eq!(std::fs::read_to_string(scratch.root.join("rootfs.ext4")).unwrap(), "disk", "the template is only ever read");
    assert!(host.spawned.lock().unwrap().is_empty(), "nothing was started");
}


#[test]
fn every_slot_this_machine_has_can_be_held_and_the_next_one_is_refused() {
    let scratch = Scratch::new("slots");
    let host = Arc::new(FakeHost::default());
    let server = scratch.server(host.clone());
    for number in 0..SLOTS {
        let id = format!("{number:020}");
        assert!(server.answer(create(&id)).is_done(), "slot {number}");
    }
    assert!(server.answer(create(OTHER)).is_failed(), "one sandbox past the last slot");
}

#[test]
fn the_client_and_the_runner_agree_over_a_real_socket() {
    let scratch = Scratch::new("socket");
    let server = Arc::new(scratch.server_with_api(Arc::new(FakeHost::default()), Arc::new(FakeApi::default())));
    let listener = UnixListener::bind(scratch.root.join("runner.sock")).unwrap();
    let serving = server.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            serving.connection(stream);
        }
    });
    let client = RunnerClient::new(scratch.root.join("runner.sock"));
    assert_eq!(client.version(), Ok(crate::config::VERSION.into()));
    assert_eq!(client.create_network(ID, true), Ok(()));
    assert_eq!(client.start(ID, 2, 512), Ok(()));
    assert_eq!(client.pause(ID), Ok(()));
    assert_eq!(client.resume(ID), Ok(()));
    assert_eq!(client.snapshot(ID), Ok(()));
    assert_eq!(client.stop(ID), Ok(()));
    assert_eq!(client.delete_network(ID), Ok(()));
    assert_eq!(client.version(), Ok(crate::config::VERSION.into()), "the connection serves one request after another");
}

#[test]
fn a_bad_request_is_refused_on_its_own_line_and_the_connection_carries_on() {
    let scratch = Scratch::new("refuse");
    let server = Arc::new(scratch.server(Arc::new(FakeHost::default())));
    let listener = UnixListener::bind(scratch.root.join("runner.sock")).unwrap();
    let serving = server.clone();
    std::thread::spawn(move || {
        if let Ok((stream, _)) = listener.accept() {
            serving.connection(stream);
        }
    });
    let mut stream = UnixStream::connect(scratch.root.join("runner.sock")).unwrap();
    let mut answers = BufReader::new(stream.try_clone().unwrap());
    let mut ask = |line: &str| {
        stream.write_all(format!("{line}\n").as_bytes()).unwrap();
        let mut answer = String::new();
        answers.read_line(&mut answer).unwrap();
        answer
    };
    assert!(ask(r#"{"op":"shell","command":"reboot"}"#).contains(r#""ok":false"#));
    assert!(ask(r#"{"op":"stop","id":"../x"}"#).contains("20 lowercase letters"));
    assert!(ask(r#"{"op":"start","id":"abcdefghij0123456789","vcpu":99,"ram_mb":1}"#).contains("out of range"));
    assert!(ask(r#"{"op":"health"}"#).contains(r#""ok":true"#), "a refusal does not cost the caller its connection");
}

#[test]
fn a_request_longer_than_the_limit_is_refused_and_the_connection_closed() {
    let scratch = Scratch::new("toolong");
    let server = Arc::new(scratch.server(Arc::new(FakeHost::default())));
    let listener = UnixListener::bind(scratch.root.join("runner.sock")).unwrap();
    let serving = server.clone();
    std::thread::spawn(move || {
        if let Ok((stream, _)) = listener.accept() {
            serving.connection(stream);
        }
    });
    let mut stream = UnixStream::connect(scratch.root.join("runner.sock")).unwrap();
    stream.write_all(&vec![b'x'; super::protocol::MAX_LINE + 1]).unwrap();
    let mut answers = BufReader::new(stream);
    let mut answer = String::new();
    answers.read_line(&mut answer).unwrap();
    assert!(answer.contains("4096 bytes"), "{answer}");
    assert_eq!(answers.read_line(&mut answer).unwrap_or(0), 0, "and then it closes");
}

#[test]
fn a_runner_that_restarted_still_knows_the_slots_its_sandboxes_hold() {
    let scratch = Scratch::new("restart");
    let host = Arc::new(FakeHost::default());
    assert!(scratch.server(host.clone()).answer(create(ID)).is_done());
    let restarted = scratch.server(host.clone());
    assert!(restarted.answer(start(ID)).is_done(), "its network is still there, and the slot is still its own");
    assert!(restarted.answer(start(OTHER)).is_failed(), "a sandbox it does not know cannot start");
    assert!(restarted.answer(create(OTHER)).is_done());
    assert_eq!(restarted.answer(create(OTHER)), Reply::Done { slot: Some(1), steps: 0 }, "the slot in use is not handed out again");
}

#[test]
fn an_id_that_is_not_one_is_refused_by_every_request_that_names_a_sandbox() {
    let scratch = Scratch::new("badid");
    let server = scratch.server(Arc::new(FakeHost::default()));
    for id in ["../escape", "a b", "--help", ""] {
        assert!(server.answer(create(id)).is_failed(), "{id:?}");
        assert!(server.answer(start(id)).is_failed(), "{id:?}");
        assert!(server.answer(Request::Stop { id: id.into() }).is_failed(), "{id:?}");
    }
    assert!(server.answer(start(ID)).is_failed(), "and nothing was made by any of them");
    assert!(!scratch.root.join("run/jail").read_dir().unwrap().any(|entry| entry.is_ok()), "no jail anywhere");
}

/// The two ways an answer can look, so a test says which it expects without matching the whole reply.
pub(super) trait AnswerKind {
    fn is_done(&self) -> bool;
    fn is_failed(&self) -> bool;
}

impl AnswerKind for Reply {
    fn is_done(&self) -> bool {
        matches!(self, Reply::Done { .. })
    }

    fn is_failed(&self) -> bool {
        matches!(self, Reply::Failed { .. })
    }
}
