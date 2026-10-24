//! The runner's Firecracker API half: pause, resume and snapshot go to the sandbox's own socket, as the three calls the plan names, and a socket that is
//! not there or refuses is a plain reason. The socket is a recorder, so none of this needs Firecracker, KVM or root.
use super::api::Api;
use super::layout::Layout;
use super::protocol::Reply;
use super::tests::{create, start, AnswerKind, FakeHost, Scratch, ID};
use super::Request;
use crate::sandbox::firecracker::api::Call;
use std::path::Path;
use std::sync::{Arc, Mutex};

/// One sandbox's Firecracker API, recording instead of listening: every call as `METHOD path body`, with the socket it was made on.
#[derive(Default)]
pub(super) struct FakeApi {
    calls: Mutex<Vec<String>>,
    /// A method and path this socket refuses, as Firecracker does when it cannot comply.
    refusing: Option<String>,
}

impl FakeApi {
    fn calls(&self) -> Vec<String> {
        self.calls.lock().unwrap().clone()
    }
}

impl Api for FakeApi {
    fn call(&self, socket: &Path, call: &Call) -> Result<(), String> {
        self.calls.lock().unwrap().push(format!("{} {} {} (on {})", call.method, call.path, call.body.as_deref().unwrap_or_default(), socket.display()));
        match &self.refusing {
            Some(refused) if format!("{} {}", call.method, call.path).starts_with(refused.as_str()) => Err("the guest is not paused".into()),
            _ => Ok(()),
        }
    }
}

#[test]
fn pause_resume_and_snapshot_are_the_firecracker_api_calls_the_plan_gives() {
    let scratch = Scratch::new("api");
    let host = Arc::new(FakeHost::default());
    let api = Arc::new(FakeApi::default());
    let server = scratch.server_with_api(host, api.clone());
    server.answer(create(ID));
    server.answer(start(ID));
    assert_eq!(server.answer(Request::Pause { id: ID.into() }), Reply::Done { slot: Some(0), steps: 1 });
    assert_eq!(server.answer(Request::Resume { id: ID.into() }), Reply::Done { slot: Some(0), steps: 1 });
    let files = Layout::new(scratch.run_dir()).files(ID).ok().unwrap();
    assert!(api.calls()[0].ends_with(&format!("(on {})", files.api_socket.display())), "the call goes to the sandbox's own socket: {:?}", api.calls()[0]);
    assert!(api.calls()[0].starts_with(r#"PATCH /vm {"state":"Paused"}"#), "{:?}", api.calls()[0]);
    assert!(api.calls()[1].starts_with(r#"PATCH /vm {"state":"Resumed"}"#), "{:?}", api.calls()[1]);
    assert_eq!(server.answer(Request::Snapshot { id: ID.into() }), Reply::Done { slot: Some(0), steps: 2 }, "a snapshot pauses first, then writes");
    let calls = api.calls();
    assert_eq!(calls.len(), 4);
    assert!(calls[2].starts_with(r#"PATCH /vm {"state":"Paused"}"#), "Firecracker writes only a paused guest's snapshot: {calls:?}");
    assert!(calls[3].starts_with(r#"PUT /snapshot/create {"mem_file_path":"/snapshot.mem","snapshot_path":"/snapshot.state","snapshot_type":"Full"}"#), "{calls:?}");
    assert_eq!(files.snapshot_state, files.jail_root.join("snapshot.state"), "the snapshot lands in the sandbox's own jail");
}

#[test]
fn a_sandbox_that_was_never_started_cannot_be_paused_resumed_or_snapshotted() {
    let scratch = Scratch::new("apinonet");
    let api = Arc::new(FakeApi::default());
    let server = scratch.server_with_api(Arc::new(FakeHost::default()), api.clone());
    for request in [Request::Pause { id: ID.into() }, Request::Resume { id: ID.into() }, Request::Snapshot { id: ID.into() }] {
        assert!(server.answer(request).is_failed(), "a sandbox with no network is refused");
    }
    assert!(api.calls().is_empty(), "and no socket is asked anything");
}

#[test]
fn a_paused_sandbox_is_still_stopped_by_its_pid() {
    let scratch = Scratch::new("pausedstop");
    let host = Arc::new(FakeHost::default());
    let api = Arc::new(FakeApi::default());
    let server = scratch.server_with_api(host.clone(), api.clone());
    server.answer(create(ID));
    server.answer(start(ID));
    assert!(server.answer(Request::Pause { id: ID.into() }).is_done());
    assert_eq!(server.answer(Request::Stop { id: ID.into() }), Reply::Done { slot: Some(0), steps: 1 }, "a paused process is still a process");
    assert_eq!(api.calls().len(), 1, "a stop does not need the API: the pid it kept is enough");
    assert!(host.stopped_now(), "the runner's own stop is what ended it");
}

#[test]
fn an_api_that_refuses_is_a_plain_reason_and_not_a_half_done_pause() {
    let scratch = Scratch::new("apirefuse");
    let api = Arc::new(FakeApi { refusing: Some("PATCH /vm".into()), ..FakeApi::default() });
    let server = scratch.server_with_api(Arc::new(FakeHost::default()), api.clone());
    server.answer(create(ID));
    server.answer(start(ID));
    assert!(server.answer(Request::Pause { id: ID.into() }).is_failed());
    assert_eq!(api.calls().len(), 1);
}
