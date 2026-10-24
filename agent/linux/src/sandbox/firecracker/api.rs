//! Firecracker's own API, as request values and nothing more: pause, resume, and a snapshot.
//!
//! Slice 3 started Firecracker with `--no-api`, which is a boot and no way in. Pause, resume and snapshot all go through the API socket that
//! Firecracker opens itself, so the jailer now hands it `--api-sock /firecracker.sock` and keeps `--config-file`: Firecracker applies the config file
//! through that same API at startup (it is the deprecated-but-supported way to boot), so one decision covers both — the boot config stays a file the
//! runner writes before the process exists, and the socket afterwards is the only way in. Making an API socket work without the config file would mean
//! booting with a series of `PUT`s, which is more requests to get wrong and no faster.
//!
//! Every request is a value built here from a validated number or a path this build names, so a test can assert the exact method, path and JSON without
//! a Firecracker binary, a KVM device or root. [`send`] is the only part that touches a socket, and it speaks HTTP/1.1 over a unix socket with the
//! standard library: no hyper, no tower, no new dependency.
//!
//! Methods and bodies, as Firecracker documents them:
//! - `PATCH /vm` with `{"state":"Paused"}` and `{"state":"Resumed"}`.
//! - `PUT /snapshot/create` with `{"snapshot_type":"Full","snapshot_path":…,"mem_file_path":…}`.
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::Duration;

/// The API socket as Firecracker sees it: the jailer chroots before Firecracker starts, so this is inside that root.
pub const SOCKET_IN_CHROOT: &str = "/firecracker.sock";
/// Where a snapshot of one sandbox goes, inside its own jail: its memory, and its device and CPU state.
pub const SNAPSHOT_STATE_IN_CHROOT: &str = "/snapshot.state";
pub const SNAPSHOT_MEMORY_IN_CHROOT: &str = "/snapshot.mem";
/// A full snapshot, not a diff: a diff is only smaller once a full one is on the machine, and templates are built from scratch.
const SNAPSHOT_TYPE: &str = "Full";
/// How long one call may take. These are three small local requests; a socket that does not answer is a sandbox that cannot be paused, not a wait.
const TIMEOUT: Duration = Duration::from_secs(5);
/// The most of an answer that is read: a refusal is a short JSON object, and nothing here needs a body.
const MAX_ANSWER: usize = 64 * 1024;
/// How much of Firecracker's refusal is kept in the reason: enough for the log line, short enough to keep whole.
const MAX_REASON: usize = 200;

/// One call to the API: the method, the path, and a body written by `serde_json`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Call {
    pub method: &'static str,
    pub path: &'static str,
    pub body: Option<String>,
}

/// `PATCH /vm {"state":"Paused"}`: the guest stops at its next point, with its memory as it is.
pub fn pause() -> Call {
    Call { method: "PATCH", path: "/vm", body: Some(serde_json::json!({ "state": "Paused" }).to_string()) }
}

/// `PATCH /vm {"state":"Resumed"}`: it carries on from where it stopped.
pub fn resume() -> Call {
    Call { method: "PATCH", path: "/vm", body: Some(serde_json::json!({ "state": "Resumed" }).to_string()) }
}

/// `PUT /snapshot/create`: the memory and the state of a paused sandbox, into the two files this build names. Firecracker takes the paths as it sees
/// them, which is inside the jail; the runner knows the same two files from the outside.
pub fn create_snapshot(state: &Path, memory: &Path) -> Result<Call, String> {
    let body = serde_json::json!({
        "snapshot_type": SNAPSHOT_TYPE,
        "snapshot_path": chroot_path(state)?,
        "mem_file_path": chroot_path(memory)?,
    });
    Ok(Call { method: "PUT", path: "/snapshot/create", body: Some(body.to_string()) })
}

/// One call, answered: 2xx is the whole answer, anything else is Firecracker's own reason, cut to a log line.
pub fn send(socket: &Path, call: &Call) -> Result<(), String> {
    let mut stream = UnixStream::connect(socket).map_err(|e| format!("cannot reach the sandbox's Firecracker API at {}: {e}", socket.display()))?;
    stream.set_read_timeout(Some(TIMEOUT)).map_err(|e| format!("the Firecracker API socket cannot be timed: {e}"))?;
    stream.set_write_timeout(Some(TIMEOUT)).map_err(|e| format!("the Firecracker API socket cannot be timed: {e}"))?;
    stream.write_all(request_text(call).as_bytes()).map_err(|e| format!("cannot ask the Firecracker API: {e}"))?;
    stream.flush().map_err(|e| format!("cannot ask the Firecracker API: {e}"))?;
    let mut answer = Vec::new();
    stream.take(MAX_ANSWER as u64).read_to_end(&mut answer).map_err(|e| format!("the Firecracker API did not answer: {e}"))?;
    accept(&answer, call)
}

/// The whole request as it goes on the socket: one request per connection, so the answer ends when the connection does.
fn request_text(call: &Call) -> String {
    let body = call.body.as_deref().unwrap_or_default();
    format!(
        "{} {} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        call.method,
        call.path,
        body.len()
    )
}

/// A 2xx is done. Anything else is a refusal, and Firecracker's own words are the reason the runner logs.
fn accept(answer: &[u8], call: &Call) -> Result<(), String> {
    let status = status_of(answer)?;
    if (200..300).contains(&status) {
        return Ok(());
    }
    Err(format!("{} {} was refused with {status}: {}", call.method, call.path, reason_of(answer)))
}

/// The status code of an HTTP/1.1 answer, or a refusal when there is no status line to read.
fn status_of(answer: &[u8]) -> Result<u16, String> {
    let head = answer.split(|byte| *byte == b'\n').next().unwrap_or_default();
    let line = String::from_utf8_lossy(head);
    let mut parts = line.split(' ');
    let protocol = parts.next().unwrap_or_default();
    if !protocol.starts_with("HTTP/") {
        return Err("the Firecracker API answered something that is not HTTP".into());
    }
    let status = parts.next().ok_or("the Firecracker API answered no status")?;
    status.trim().parse::<u16>().map_err(|_| format!("the Firecracker API answered a status this build cannot read: {status:?}"))
}

/// The first words of what Firecracker said after its headers: its own error, and never a path of ours that matters.
fn reason_of(answer: &[u8]) -> String {
    let body: &[u8] = answer.windows(4).position(|window| window == b"\r\n\r\n").map_or(&[], |at| &answer[at + 4..]);
    String::from_utf8_lossy(body).trim().chars().take(MAX_REASON).collect()
}

/// A snapshot path as Firecracker reads it: absolute within its chroot, and text this machine can hand to a program.
fn chroot_path(path: &Path) -> Result<String, String> {
    if !path.is_absolute() {
        return Err(format!("{} must be an absolute path inside the chroot", path.display()));
    }
    let text = path.to_str().ok_or_else(|| format!("{} is not a path this machine can use", path.display()))?;
    if text.contains('\0') {
        return Err("a path cannot hold a NUL byte".into());
    }
    Ok(text.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};
    use std::io::{BufRead, BufReader};
    use std::os::unix::net::UnixListener;
    use std::path::PathBuf;

    fn scratch(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("ms-api-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        root
    }

    fn body_of(call: &Call) -> Value {
        serde_json::from_str(call.body.as_deref().unwrap()).expect("a body this module wrote is JSON")
    }

    #[test]
    fn pause_and_resume_are_one_patch_of_the_vm_state() {
        assert_eq!((pause().method, pause().path), ("PATCH", "/vm"));
        assert_eq!(pause().body.as_deref(), Some(r#"{"state":"Paused"}"#));
        assert_eq!((resume().method, resume().path), ("PATCH", "/vm"));
        assert_eq!(resume().body.as_deref(), Some(r#"{"state":"Resumed"}"#));
    }

    #[test]
    fn a_snapshot_is_a_full_one_into_the_two_files_this_build_names() {
        let call = create_snapshot(Path::new(SNAPSHOT_STATE_IN_CHROOT), Path::new(SNAPSHOT_MEMORY_IN_CHROOT)).ok().unwrap();
        assert_eq!((call.method, call.path), ("PUT", "/snapshot/create"));
        assert_eq!(body_of(&call), json!({"snapshot_type": "Full", "snapshot_path": "/snapshot.state", "mem_file_path": "/snapshot.mem"}));
        assert_eq!(
            call.body.as_deref(),
            Some(r#"{"mem_file_path":"/snapshot.mem","snapshot_path":"/snapshot.state","snapshot_type":"Full"}"#),
            "and it is written by serde_json, in one fixed order"
        );
    }

    #[test]
    fn a_snapshot_path_a_program_cannot_be_given_is_refused() {
        for bad in ["snapshot.state", "./state", ""] {
            assert!(create_snapshot(Path::new(bad), Path::new(SNAPSHOT_MEMORY_IN_CHROOT)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn a_call_goes_out_as_one_http_request_and_a_2xx_is_done() {
        let socket = scratch("send").join("firecracker.sock");
        let listener = UnixListener::bind(&socket).unwrap();
        let serving = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut request = String::new();
            reader.read_line(&mut request).unwrap();
            let mut headers = String::new();
            loop {
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                if line == "\r\n" {
                    break;
                }
                headers.push_str(&line);
            }
            let length: usize = headers.lines().find_map(|line| line.strip_prefix("Content-Length: ")).unwrap().trim().parse().unwrap();
            let mut body = vec![0; length];
            reader.read_exact(&mut body).unwrap();
            stream.write_all(b"HTTP/1.1 204 No Content\r\nServer: Firecracker API\r\n\r\n").unwrap();
            format!("{request}{headers}{}", String::from_utf8(body).unwrap())
        });
        assert_eq!(send(&socket, &pause()), Ok(()));
        let request = serving.join().unwrap();
        assert!(request.starts_with("PATCH /vm HTTP/1.1\r\n"), "{request:?}");
        assert!(request.contains("Content-Length: 18\r\n"), "{request:?}");
        assert!(request.ends_with(r#"{"state":"Paused"}"#), "{request:?}");
        assert!(request.contains("Connection: close\r\n"), "one request per connection, so the answer ends: {request:?}");
    }

    #[test]
    fn a_refusal_is_firecrackers_own_reason_and_a_socket_that_is_not_there_is_a_plain_reason() {
        let socket = scratch("refuse").join("firecracker.sock");
        let listener = UnixListener::bind(&socket).unwrap();
        let serving = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buffer = [0_u8; 1024];
            let _ = std::io::Read::read(&mut stream, &mut buffer).unwrap();
            stream.write_all(b"HTTP/1.1 400 Bad Request\r\n\r\n{\"fault_message\":\"not paused\"}").unwrap();
        });
        let refused = send(&socket, &create_snapshot(Path::new(SNAPSHOT_STATE_IN_CHROOT), Path::new(SNAPSHOT_MEMORY_IN_CHROOT)).unwrap()).err();
        serving.join().unwrap();
        assert_eq!(refused.as_deref(), Some(r#"PUT /snapshot/create was refused with 400: {"fault_message":"not paused"}"#));
        let missing = send(&scratch("gone").join("nothing.sock"), &resume()).err();
        assert!(missing.as_deref().is_some_and(|reason| reason.contains("cannot reach")), "{missing:?}");
    }
}
