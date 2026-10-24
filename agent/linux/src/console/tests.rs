//! The console end to end on the real HTTP and WebSocket code: the simulated engine runs a fake program (`cat`, `sleep`, `sh`) on a real pty instead of `incus exec`,
//! so no Incus is needed. Also the refusals before the upgrade, and the Incus engine's attach with a scripted runner.
use super::{attach_failure, Consoles};
use crate::cpu::CpuOffer;
use crate::engine::{default_capabilities, Engine, SimulatedEngine};
use crate::http::{router, App};
use crate::incus::{IncusEngine, Runner};
use crate::models::{Capabilities, EngineError, GpuMode, Kind};
use crate::ssh_keys_tests::{send, service_over, TOKEN};
use crate::validate::CreateRequest;
use axum::http::StatusCode;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::io::Write;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{MaybeTlsStream, WebSocketStream};

const WAIT: Duration = Duration::from_secs(10);
const WORKLOAD: &str = "w-box";
type Client = WebSocketStream<MaybeTlsStream<TcpStream>>;

fn request(kind: Kind) -> CreateRequest {
    CreateRequest { command_id: "c-1".into(), name: "box".into(), kind, cpu: 1, ram_mb: 512, disk_gb: 1, gpu_mode: GpuMode::None, image: None, gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None }
}

struct Machine {
    engine: Arc<SimulatedEngine>,
    address: SocketAddr,
}

/// A simulated machine with one running container, served on a real local port.
async fn machine(program: &str, arguments: &[&str]) -> Machine {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create(WORKLOAD, &request(Kind::Container)).ok().unwrap();
    engine.set_attach(program, arguments);
    let app = App::new(service_over(engine.clone()), TOKEN.into(), 10);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    tokio::spawn(async move { axum::serve(listener, router(app).into_make_service_with_connect_info::<SocketAddr>()).await });
    Machine { engine, address }
}

#[allow(clippy::result_large_err)] // the library error is used as it is
async fn open(machine: &Machine, token: &str) -> Result<Client, tokio_tungstenite::tungstenite::Error> {
    let mut request = format!("ws://{}/v1/workloads/{WORKLOAD}/terminal", machine.address).into_client_request().unwrap();
    request.headers_mut().insert("authorization", format!("Bearer {token}").parse().unwrap());
    tokio_tungstenite::connect_async(request).await.map(|(client, _)| client)
}

/// Opens a console once the previous one on the workload is gone and its place is given back.
async fn open_when_free(machine: &Machine) -> Client {
    let deadline = Instant::now() + WAIT;
    loop {
        match open(machine, TOKEN).await {
            Ok(client) => return client,
            Err(cause) => assert!(Instant::now() < deadline, "the place never came back: {cause}"),
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

/// Reads output until it contains `wanted`; fails on a close or after the time limit.
async fn read_until(client: &mut Client, wanted: &str) -> String {
    let mut seen = String::new();
    let deadline = Instant::now() + WAIT;
    while !seen.contains(wanted) {
        let next = tokio::time::timeout(deadline.saturating_duration_since(Instant::now()), client.next()).await;
        match next {
            Ok(Some(Ok(Message::Binary(bytes)))) => seen.push_str(&String::from_utf8_lossy(&bytes)),
            other => panic!("wanted {wanted:?}, saw {seen:?} then {other:?}"),
        }
    }
    seen
}

/// The close frame the server sends: its code and reason.
async fn closing(client: &mut Client) -> (u16, String) {
    loop {
        match tokio::time::timeout(WAIT, client.next()).await {
            Ok(Some(Ok(Message::Close(Some(frame))))) => return (frame.code.into(), frame.reason.to_string()),
            Ok(Some(Ok(Message::Binary(_)))) => continue,
            other => panic!("expected a close frame, saw {other:?}"),
        }
    }
}

fn alive(pid: i32) -> bool {
    unsafe { libc::kill(pid, 0) == 0 }
}

async fn gone(pid: i32) -> bool {
    let deadline = Instant::now() + WAIT;
    while Instant::now() < deadline {
        if !alive(pid) {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    false
}

/// Starts a shell that prints its process id and then becomes `sleep`, and returns the id.
async fn sleeper(machine: &Machine, client: &mut Client) -> i32 {
    let _ = machine;
    let text = read_until(client, "pid=").await;
    let tail = &text[text.find("pid=").unwrap() + 4..];
    let digits: String = tail.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().unwrap()
}

const SLEEPER: [&str; 2] = ["-c", "echo pid=$$; exec sleep 60"];

// ---- before the upgrade

#[tokio::test]
async fn without_the_right_token_the_answer_is_401_and_with_it_a_plain_get_is_426() {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create(WORKLOAD, &request(Kind::Container)).ok().unwrap();
    let service = service_over(engine);
    let path = format!("/v1/workloads/{WORKLOAD}/terminal");
    assert_eq!(send(&service, "GET", &path, "", "wrong").await.0, StatusCode::UNAUTHORIZED);
    let (status, body) = send(&service, "GET", &path, "", TOKEN).await;
    assert_eq!((status, body["error"]["code"].clone()), (StatusCode::UPGRADE_REQUIRED, json!("upgrade_required")));
}

#[tokio::test]
async fn an_unknown_or_malformed_id_is_404() {
    let service = service_over(Arc::new(SimulatedEngine::new(default_capabilities())));
    for id in ["w-none", "..", "A%20B"] {
        assert_eq!(send(&service, "GET", &format!("/v1/workloads/{id}/terminal"), "", TOKEN).await.0, StatusCode::NOT_FOUND, "{id}");
    }
}

#[tokio::test]
async fn a_stopped_workload_is_409_not_running() {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create(WORKLOAD, &request(Kind::Container)).ok().unwrap();
    engine.set_running(WORKLOAD, false).ok().unwrap();
    let (status, body) = send(&service_over(engine), "GET", &format!("/v1/workloads/{WORKLOAD}/terminal"), "", TOKEN).await;
    assert_eq!((status, body["error"]["code"].clone()), (StatusCode::CONFLICT, json!("not_running")));
}

#[tokio::test]
async fn the_bad_token_limit_applies_to_the_console_route() {
    let machine = machine("/bin/cat", &[]).await;
    for _ in 0..10 {
        assert!(open(&machine, "wrong").await.is_err());
    }
    let refused = open(&machine, TOKEN).await;
    assert!(matches!(refused, Err(tokio_tungstenite::tungstenite::Error::Http(ref r)) if r.status() == StatusCode::TOO_MANY_REQUESTS));
}

#[test]
fn a_vm_that_cannot_be_entered_is_409_no_agent_and_a_container_failure_is_a_plain_500() {
    let vm = attach_failure(Kind::Vm, EngineError::Failed("no agent".into()));
    assert_eq!(vm.status(), StatusCode::CONFLICT);
    assert_eq!(attach_failure(Kind::Container, EngineError::Failed("secret detail".into())).status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(attach_failure(Kind::Vm, EngineError::NotFound).status(), StatusCode::NOT_FOUND);
}

#[test]
fn one_console_per_workload_and_the_place_comes_back_on_drop() {
    let consoles = Consoles::default();
    let slot = consoles.claim("w-1").expect("first");
    assert!(consoles.is_open("w-1") && consoles.claim("w-1").is_none());
    assert!(consoles.claim("w-2").is_some(), "another workload is free");
    drop(slot);
    assert!(!consoles.is_open("w-1") && consoles.claim("w-1").is_some());
}

// ---- the Incus engine's attach

struct ScriptedIncus {
    list: String,
    exec_works: bool,
}

impl Runner for ScriptedIncus {
    fn program(&self) -> String {
        "/opt/incus".into()
    }

    fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        match arguments.first().map(String::as_str) {
            Some("list") => Ok(self.list.clone()),
            Some("exec") if !self.exec_works => Err(EngineError::Failed("VM agent is not running".into())),
            _ => Ok(String::new()),
        }
    }

    fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.run(arguments, timeout)
    }
}

fn incus_listing(kind: &str, gpu_mode: &str, address: Option<&str>) -> String {
    let state = match address {
        Some(address) => format!(r#""state":{{"network":{{"eth0":{{"addresses":[{{"family":"inet","scope":"global","address":"{address}"}}]}}}}}}"#),
        None => r#""state":null"#.to_string(),
    };
    format!(
        r#"[{{"name":"ms-w-1","status":"Running","config":{{"user.metaservice.id":"w-1","user.metaservice.name":"d","user.metaservice.kind":"{kind}","user.metaservice.gpu_mode":"{gpu_mode}","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1"}},{state}}}]"#
    )
}

fn incus_with(listing: &str, exec_works: bool) -> IncusEngine {
    let capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY };
    IncusEngine::new(Arc::new(ScriptedIncus { list: listing.to_string(), exec_works }), capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1)
}

fn incus(kind: &str, exec_works: bool) -> IncusEngine {
    incus_with(&incus_listing(kind, "none", None), exec_works)
}

#[test]
fn a_container_gets_the_fixed_incus_exec_command_without_any_probe() {
    let command = incus("container", false).attach("w-1").ok().unwrap();
    assert_eq!(command.program, "/opt/incus");
    assert_eq!(&command.arguments[..2], ["exec", "ms-w-1"]);
    assert_eq!(command.arguments.last().map(String::as_str), Some("exec bash -l 2>/dev/null || exec sh -l"));
}

#[test]
fn a_container_with_an_address_gets_a_root_prompt_that_names_it() {
    let command = incus_with(&incus_listing("container", "none", Some("10.0.0.5")), false).attach("w-1").ok().unwrap();
    let script = command.arguments.last().unwrap();
    assert!(script.contains("root@10.0.0.5:\\w# "), "{script}");
    assert!(!script.contains(" -l"), "{script}");
}

#[test]
fn a_gpu_container_gets_the_same_console_command_as_a_plain_one() {
    for address in [None, Some("10.0.0.5")] {
        let plain = incus_with(&incus_listing("container", "none", address), false).attach("w-1").ok().unwrap();
        let gpu = incus_with(&incus_listing("container", "container", address), false).attach("w-1").ok().unwrap();
        assert_eq!(plain, gpu, "the GPU never changes the console ({address:?})");
    }
}

/// Runs the exact prompt command on a real pty with this machine's sh and bash: the root prompt must appear, and PATH must still find programs.
/// The keys are typed only once the prompt is drawn, as a person does: input written before the shell takes the pty is flushed by bash.
#[test]
fn the_prompt_command_really_shows_the_address_and_keeps_a_usable_path() {
    let command = incus_with(&incus_listing("container", "none", Some("10.0.0.5")), false).attach("w-1").ok().unwrap();
    let script = command.arguments.last().cloned().unwrap();
    let process = super::pty::PtyProcess::spawn("/bin/sh", &["-c".into(), script], super::frames::START_SIZE).unwrap();
    let (mut reader, mut writer) = (process.reader().unwrap(), process.writer().unwrap());
    let seen = Arc::new(Mutex::new(String::new()));
    let (done_tx, done_rx) = std::sync::mpsc::channel();
    let sink = Arc::clone(&seen);
    std::thread::spawn(move || {
        let mut buffer = [0u8; 4096];
        loop {
            match super::pty::read_output(&mut reader, &mut buffer) {
                Ok(0) | Err(_) => break,
                Ok(count) => {
                    sink.lock().unwrap().push_str(&String::from_utf8_lossy(&buffer[..count]));
                    let finished = {
                        let text = sink.lock().unwrap();
                        text.contains("ready-42") && text.contains("path-ok")
                    };
                    if finished { break; }
                }
            }
        }
        let _ = done_tx.send(());
    });
    wait_for_output(&seen, "root@10.0.0.5:");
    writer.write_all(b"echo ready-$((6*7)); command -v sh >/dev/null && echo path-ok\n").unwrap();
    done_rx.recv_timeout(WAIT).expect("the prompt shell answered");
    drop(process);
    let text = seen.lock().unwrap().clone();
    assert!(text.contains("root@10.0.0.5:"), "{text}");
    assert!(text.contains("ready-42") && text.contains("path-ok"), "{text}");
}

/// Waits until the output seen so far contains `wanted`, or fails after WAIT with everything that was seen.
fn wait_for_output(seen: &Arc<Mutex<String>>, wanted: &str) {
    let end = Instant::now() + WAIT;
    while Instant::now() < end {
        if seen.lock().unwrap().contains(wanted) { return; }
        std::thread::sleep(Duration::from_millis(20));
    }
    panic!("the terminal never said {wanted}: {}", seen.lock().unwrap());
}

#[test]
fn a_vm_without_the_guest_agent_is_refused_with_the_plain_reason() {
    let Err(EngineError::Failed(reason)) = incus("vm", false).attach("w-1") else { panic!("expected a refusal") };
    assert_eq!(reason, crate::incus::NO_AGENT_MESSAGE);
    assert!(incus("vm", true).attach("w-1").is_ok(), "a VM that answers can be entered");
    assert!(matches!(incus("vm", true).attach("w-none"), Err(EngineError::NotFound)));
}

// ---- the open console

#[tokio::test]
async fn what_is_typed_comes_back_through_the_pty_over_the_socket() {
    let machine = machine("/bin/cat", &[]).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    client.send(Message::Binary(b"hello console\n".to_vec())).await.unwrap();
    read_until(&mut client, "hello console").await;
}

#[tokio::test]
async fn a_resize_frame_changes_the_window_the_program_sees() {
    let machine = machine("/bin/sh", &["-c", "stty size; read go; stty size"]).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    read_until(&mut client, "24 80").await;
    client.send(Message::Text(r#"{"resize":[132,43]}"#.into())).await.unwrap();
    client.send(Message::Binary(b"\n".to_vec())).await.unwrap();
    read_until(&mut client, "43 132").await;
}

#[tokio::test]
async fn an_oversized_frame_or_a_bad_resize_closes_with_1008() {
    let machine = machine("/bin/cat", &[]).await;
    let bad: [Message; 3] = [
        Message::Binary(vec![b'x'; super::frames::MAX_INPUT_BYTES + 1]),
        Message::Text(r#"{"resize":[501,24]}"#.into()),
        Message::Text("not json".into()),
    ];
    for frame in bad {
        let mut client = open_when_free(&machine).await;
        client.send(frame).await.unwrap();
        assert_eq!(closing(&mut client).await.0, 1008);
    }
}

#[tokio::test]
async fn a_frame_at_the_cap_is_accepted_whole() {
    let machine = machine("/bin/sh", &["-c", "stty raw -echo; echo ready; head -c 65537 | wc -c"]).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    read_until(&mut client, "ready").await;
    client.send(Message::Binary(vec![b'x'; super::frames::MAX_INPUT_BYTES])).await.unwrap();
    client.send(Message::Binary(b"y".to_vec())).await.unwrap();
    read_until(&mut client, "65537").await;
}

#[tokio::test]
async fn a_second_console_on_the_same_workload_is_refused_until_the_first_is_gone() {
    let machine = machine("/bin/cat", &[]).await;
    let mut first = open(&machine, TOKEN).await.unwrap();
    let second = open(&machine, TOKEN).await;
    assert!(matches!(second, Err(tokio_tungstenite::tungstenite::Error::Http(ref r)) if r.status() == StatusCode::CONFLICT));
    first.close(None).await.unwrap();
    drop(first);
    open_when_free(&machine).await;
}

#[tokio::test]
async fn closing_the_socket_kills_the_program_and_leaves_nothing_behind() {
    let machine = machine("/bin/sh", &SLEEPER).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    let pid = sleeper(&machine, &mut client).await;
    assert!(alive(pid));
    drop(client);
    assert!(gone(pid).await, "the program was killed and reaped");
}

#[tokio::test]
async fn stopping_the_workload_ends_the_console_with_1000_and_kills_the_program() {
    let machine = machine("/bin/sh", &SLEEPER).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    let pid = sleeper(&machine, &mut client).await;
    machine.engine.set_running(WORKLOAD, false).ok().unwrap();
    assert_eq!(closing(&mut client).await, (1000, "the workload stopped".to_string()));
    assert!(gone(pid).await);
}

#[tokio::test]
async fn deleting_the_workload_ends_the_console_with_1000() {
    let machine = machine("/bin/sh", &SLEEPER).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    let pid = sleeper(&machine, &mut client).await;
    machine.engine.delete(WORKLOAD).ok().unwrap();
    assert_eq!(closing(&mut client).await, (1000, "the workload was deleted".to_string()));
    assert!(gone(pid).await);
}

#[tokio::test]
async fn a_shell_that_exits_closes_the_console_with_1000() {
    let machine = machine("/bin/sh", &["-c", "echo bye"]).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    assert_eq!(closing(&mut client).await, (1000, "the shell ended".to_string()));
}

#[tokio::test]
async fn a_program_that_cannot_start_closes_with_1011_and_frees_the_place() {
    let machine = machine("/nonexistent/program", &[]).await;
    let mut client = open(&machine, TOKEN).await.unwrap();
    assert_eq!(closing(&mut client).await.0, 1011);
    machine.engine.set_attach("/bin/cat", &[]);
    open_when_free(&machine).await;
}
