//! The sandbox routes and the store behind them: the status codes the contract gives, the end time that takes a sandbox out, the idempotent retry and
//! delete, the events, and what the facts say. Everything runs on the simulated engine, so nothing here needs root, KVM or Firecracker.
use super::engine::{Limits, Sample, SandboxEngine, SimulatedSandboxEngine, Template};
use super::record::{OnEnd, Sandbox};
use super::{Refusal, Sandboxes};
use crate::budget::SpaceBudget;
use crate::engine::{default_capabilities, SimulatedEngine};
use crate::http::{router, App};
use crate::models::*;
use crate::service::Service;
use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tower::ServiceExt;

const TOKEN: &str = "test-token";
const ID: &str = "abcdefghij0123456789";
const OTHER: &str = "zyxwvutsrq9876543210";
/// The sandbox time of the check: far enough away that nothing ends by itself.
const LATER: &str = "2027-01-01T00:00:00Z";

fn limits() -> Limits {
    Limits { max_running: 4, max_vcpu: 8, max_ram_mb: 4096, max_disk_mb: 8192 }
}

fn specs() -> Specs {
    Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 8, cpu_model: None, ram_total_mb: 65536, disk_total_gb: 2000, gpu: Vec::new(), hardware: None }
}

fn service(sandboxes: Arc<Sandboxes>) -> Arc<Service> {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    let budget = SpaceBudget::new(65536, 2000);
    Arc::new(Service::new(engine, budget, specs(), "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), Arc::new(NoChat), || None).with_sandboxes(sandboxes))
}

struct NoChat;

impl crate::service::BundleInstalling for NoChat {
    fn install(&self, _request: &crate::validate::BundleRequest) -> Result<std::collections::HashMap<String, String>, String> {
        Ok(std::collections::HashMap::new())
    }

    fn uninstall(&self, _workload_id: Option<&str>) -> Result<(), String> {
        Ok(())
    }

    fn installed_version(&self) -> Option<String> {
        None
    }
}

/// A helper that runs the simulated sandbox engine, with nothing in it yet.
fn helper() -> (Arc<Sandboxes>, Arc<Service>) {
    let sandboxes = Sandboxes::new(Some(Arc::new(SimulatedSandboxEngine::new(limits()))));
    (sandboxes.clone(), service(sandboxes))
}

/// An engine that makes sandboxes but has no way to stop a guest where it is: what a `409 not_pausable` comes from.
struct NoPauseEngine(SimulatedSandboxEngine);

impl SandboxEngine for NoPauseEngine {
    fn name(&self) -> &'static str {
        self.0.name()
    }

    fn limits(&self) -> Limits {
        self.0.limits()
    }

    fn templates(&self) -> Vec<Template> {
        self.0.templates()
    }

    fn create(&self, sandbox: &Sandbox) -> Result<(), String> {
        self.0.create(sandbox)
    }

    fn stop(&self, id: &str) -> Result<(), String> {
        self.0.stop(id)
    }

    fn delete(&self, id: &str) -> Result<(), String> {
        self.0.delete(id)
    }

    fn metrics(&self, sandbox: &Sandbox, now: u64) -> Vec<Sample> {
        self.0.metrics(sandbox, now)
    }
}

fn body(id: &str, end_at: &str) -> Value {
    json!({"id": id, "template": "base", "vcpu": 2, "ram_mb": 512, "disk_mb": 1024, "end_at": end_at, "on_end": "kill", "internet": false,
        "env_vars": {"A": "1"}, "access_token": "t".repeat(40)})
}

async fn send(service: &Arc<Service>, method: &str, path: &str, body: &Value, token: &str) -> (StatusCode, Value) {
    let app = router(App::new(service.clone(), TOKEN.into(), 10));
    let mut request = Request::builder().method(method).uri(path).header("authorization", format!("Bearer {token}")).body(Body::from(body.to_string())).unwrap();
    request.extensions_mut().insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))));
    let response = app.oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

/// The port route carries the command token in its own header, so the caller's `Authorization` can reach the program inside.
async fn send_port(service: &Arc<Service>, method: &str, path: &str, credentials: &str) -> (StatusCode, Value) {
    let app = router(App::new(service.clone(), TOKEN.into(), 10));
    let mut request = Request::builder().method(method).uri(path).header("x-metaservice-token", credentials).body(Body::empty()).unwrap();
    request.extensions_mut().insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 40000))));
    let response = app.oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

async fn create(service: &Arc<Service>, sandbox: Value) -> (StatusCode, Value) {
    send(service, "POST", "/v1/sandboxes", &sandbox, TOKEN).await
}

// ---- the routes

#[tokio::test]
async fn every_sandbox_route_needs_the_command_token() {
    let (_, service) = helper();
    for path in ["/v1/sandboxes", "/v1/sandbox-events?after=0", "/v1/sandbox-templates"] {
        let (status, answer) = send(&service, "GET", path, &Value::Null, "wrong").await;
        assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::UNAUTHORIZED, json!("unauthorized")), "GET {path}");
    }
    let (status, _) = send(&service, "POST", "/v1/sandboxes", &body(ID, LATER), TOKEN).await;
    assert_eq!(status, StatusCode::CREATED, "the right token works");
}

#[tokio::test]
async fn a_helper_that_cannot_run_sandboxes_answers_404_everywhere_and_says_nothing_in_its_facts() {
    let service = service(Sandboxes::disabled());
    let paths = ["/v1/sandboxes".to_string(), "/v1/sandbox-events?after=0".to_string(), "/v1/sandbox-templates".to_string(),
        format!("/v1/sandboxes/{ID}"), format!("/v1/sandboxes/{ID}/metrics")];
    for path in paths {
        let (status, _) = send(&service, "GET", &path, &Value::Null, TOKEN).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "GET {path}");
    }
    let (status, _) = create(&service, body(ID, LATER)).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let facts = serde_json::to_value(service.facts().await.ok().unwrap()).unwrap();
    assert_eq!(facts["capabilities"]["sandbox"], json!(false));
    assert!(facts.get("sandbox").is_none(), "a helper with no sandbox engine says nothing about them");
}

#[tokio::test]
async fn a_create_answers_201_with_the_contract_shape_and_its_facts_say_one_is_running() {
    let (sandboxes, service) = helper();
    let (status, answer) = create(&service, body(ID, LATER)).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(answer["id"], ID);
    assert_eq!(answer["state"], "running");
    assert_eq!((answer["template"].clone(), answer["build"].clone()), (json!("base"), json!("1")));
    assert_eq!((&answer["vcpu"], &answer["ram_mb"], &answer["disk_mb"]), (&json!(2), &json!(512), &json!(1024)));
    assert!(answer["started_at"].as_str().is_some_and(|time| time.ends_with('Z')));
    assert_eq!(answer["end_at"], LATER);
    assert!(answer["running_ms"].as_u64().is_some());
    let facts = service.facts().await.ok().unwrap();
    let json = serde_json::to_value(&facts).unwrap();
    assert_eq!(json["capabilities"]["sandbox"], json!(true));
    assert_eq!((&json["sandbox"]["engine"]["name"], &json["sandbox"]["running"]), (&json!("simulated"), &json!(1)));
    assert_eq!((&json["sandbox"]["booked"]["vcpu"], &json["sandbox"]["booked"]["ram_mb"], &json["sandbox"]["booked"]["disk_mb"]), (&json!(2), &json!(512), &json!(1024)));
    assert_eq!(json["sandbox"]["templates"], json!([{"id": "base", "build": "1", "ready": true}]));
    assert_eq!(json["sandbox"]["changes"], json!(1), "the start event moved the change number");
    assert_eq!(sandboxes.list().ok().unwrap().len(), 1);
}

#[tokio::test]
async fn the_same_id_and_body_again_is_the_same_sandbox_and_a_different_body_is_refused() {
    let (_, service) = helper();
    assert_eq!(create(&service, body(ID, LATER)).await.0, StatusCode::CREATED);
    let (status, again) = create(&service, body(ID, LATER)).await;
    assert_eq!((status, again["id"].clone()), (StatusCode::OK, json!(ID)), "a retry is answered with the sandbox it already made");
    let (status, answer) = create(&service, body(ID, "2027-02-01T00:00:00Z")).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::CONFLICT, json!("id_taken")));
    let (_, list) = send(&service, "GET", "/v1/sandboxes", &Value::Null, TOKEN).await;
    assert_eq!(list["sandboxes"].as_array().unwrap().len(), 1, "only one sandbox was ever made");
}

#[tokio::test]
async fn an_id_a_sandbox_has_already_had_is_never_given_to_a_second_one() {
    let (sandboxes, service) = helper();
    assert_eq!(create(&service, body(ID, LATER)).await.0, StatusCode::CREATED);
    assert_eq!(send(&service, "DELETE", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::NO_CONTENT);
    let (status, answer) = create(&service, body(ID, LATER)).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::CONFLICT, json!("id_taken")), "a retry after the sandbox is gone must not make a new one");
    assert!(sandboxes.list().ok().unwrap().is_empty());
}

#[tokio::test]
async fn a_template_this_machine_does_not_have_is_a_409_and_nothing_is_made() {
    let (sandboxes, service) = helper();
    let mut unknown = body(ID, LATER);
    unknown["template"] = json!("code-interpreter-v1");
    let (status, answer) = create(&service, unknown).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::CONFLICT, json!("template_not_ready")));
    assert!(sandboxes.list().ok().unwrap().is_empty());
}

#[tokio::test]
async fn a_machine_with_no_room_left_refuses_with_the_numbers() {
    let sandboxes = Sandboxes::new(Some(Arc::new(SimulatedSandboxEngine::new(Limits { max_running: 1, max_vcpu: 8, max_ram_mb: 4096, max_disk_mb: 8192 }))));
    let service = service(sandboxes);
    assert_eq!(create(&service, body(ID, LATER)).await.0, StatusCode::CREATED);
    let (status, answer) = create(&service, body(OTHER, LATER)).await;
    assert_eq!((status, answer["error"]["code"].clone(), answer["error"]["resource"].clone()), (StatusCode::CONFLICT, json!("not_enough_room"), json!("slots")));
    assert_eq!((answer["error"]["needed"].clone(), answer["error"]["free"].clone()), (json!(1), json!(0)));
}

#[tokio::test]
async fn a_size_this_machine_cannot_take_is_a_409_too() {
    let sandboxes = Sandboxes::new(Some(Arc::new(SimulatedSandboxEngine::new(Limits { max_running: 4, max_vcpu: 2, max_ram_mb: 4096, max_disk_mb: 8192 }))));
    let service = service(sandboxes);
    let mut big = body(ID, LATER);
    big["vcpu"] = json!(4);
    let (status, answer) = create(&service, big).await;
    assert_eq!((status, answer["error"]["resource"].clone()), (StatusCode::CONFLICT, json!("vcpu")));
}

#[tokio::test]
async fn every_body_the_contract_does_not_allow_is_a_400() {
    let (_, service) = helper();
    let mut extra = body(ID, LATER);
    extra["pause_on_end"] = json!(true);
    let mut no_token = body(ID, LATER);
    no_token.as_object_mut().unwrap().remove("access_token");
    for bad in [extra, no_token, body("short", LATER), body("ABCDEFGHIJ0123456789", LATER), json!({}), json!({"id": ID})] {
        let (status, answer) = create(&service, bad.clone()).await;
        assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_REQUEST, json!("invalid_input")), "{bad}");
    }
    let (status, _) = send(&service, "POST", "/v1/sandboxes", &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an empty body is not a create");
}

#[tokio::test]
async fn an_unknown_id_is_a_404_on_every_route_that_names_one() {
    let (_, service) = helper();
    for (method, path) in [("GET", format!("/v1/sandboxes/{OTHER}")), ("DELETE", format!("/v1/sandboxes/{OTHER}")), ("GET", format!("/v1/sandboxes/{OTHER}/metrics")),
                           ("PUT", format!("/v1/sandboxes/{OTHER}/end")), ("GET", "/v1/sandboxes/nosuchid01234567890".to_string()),
                           ("PUT", format!("/v1/sandboxes/{OTHER}/pause")), ("PUT", format!("/v1/sandboxes/{OTHER}/resume"))] {
        let (status, _) = send(&service, method, &path, &json!({"end_at": LATER, "on_end": "kill"}), TOKEN).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {path}");
    }
}

#[tokio::test]
async fn a_pause_and_a_resume_answer_the_sandbox_with_its_end_time_where_it_was() {
    let (_, service) = helper();
    create(&service, body(ID, LATER)).await;
    let (status, paused) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/pause"), &Value::Null, TOKEN).await;
    assert_eq!((status, paused["state"].clone(), paused["end_at"].clone()), (StatusCode::OK, json!("paused"), json!(LATER)), "a pause does not move the end time");
    let (_, list) = send(&service, "GET", "/v1/sandboxes", &Value::Null, TOKEN).await;
    assert_eq!(list["sandboxes"][0]["state"], "paused", "the list says which sandboxes are paused");
    let facts = serde_json::to_value(service.facts().await.ok().unwrap()).unwrap();
    assert_eq!((&facts["sandbox"]["running"], &facts["sandbox"]["paused"], &facts["sandbox"]["booked"]["ram_mb"]), (&json!(0), &json!(1), &json!(0)), "a paused sandbox holds no memory");
    let (status, paused_again) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/pause"), &Value::Null, TOKEN).await;
    assert_eq!((status, paused_again["state"].clone()), (StatusCode::OK, json!("paused")), "a second pause changes nothing");
    let (status, resumed) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/resume"), &Value::Null, TOKEN).await;
    assert_eq!((status, resumed["state"].clone(), resumed["end_at"].clone()), (StatusCode::OK, json!("running"), json!(LATER)));
    let (status, _) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/resume"), &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::OK, "a resume of one that runs changes nothing");
    let (_, events) = send(&service, "GET", "/v1/sandbox-events?after=0", &Value::Null, TOKEN).await;
    let kinds: Vec<Value> = events["events"].as_array().unwrap().iter().map(|event| event["kind"].clone()).collect();
    assert_eq!(kinds, [json!("started"), json!("paused"), json!("resumed")], "one event for each thing that happened, and no more");
}

#[tokio::test]
async fn a_paused_sandbox_is_deleted_and_ends_on_its_time_like_any_other() {
    let (sandboxes, service) = helper();
    create(&service, body(ID, LATER)).await;
    send(&service, "PUT", &format!("/v1/sandboxes/{ID}/pause"), &Value::Null, TOKEN).await;
    assert_eq!(send(&service, "DELETE", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::NO_CONTENT);
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::NOT_FOUND);
    create(&service, body(OTHER, LATER)).await;
    send(&service, "PUT", &format!("/v1/sandboxes/{OTHER}/pause"), &Value::Null, TOKEN).await;
    let now = json!({"end_at": super::time::iso8601(super::time::now()), "on_end": "kill"});
    send(&service, "PUT", &format!("/v1/sandboxes/{OTHER}/end"), &now, TOKEN).await;
    sandboxes.sweep();
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{OTHER}"), &Value::Null, TOKEN).await.0, StatusCode::NOT_FOUND, "a pause never outlives its end time");
}

#[tokio::test]
async fn an_engine_that_cannot_pause_is_a_409_and_the_record_says_running() {
    let sandboxes = Sandboxes::new(Some(Arc::new(NoPauseEngine(SimulatedSandboxEngine::new(limits())))));
    let service = service(sandboxes);
    create(&service, body(ID, LATER)).await;
    let (status, answer) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/pause"), &Value::Null, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::CONFLICT, json!("not_pausable")));
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.1["state"], "running", "a 409 never leaves the record saying paused");
}

#[tokio::test]
async fn a_delete_answers_204_twice_and_a_sandbox_that_never_was_here_is_a_404() {
    let (_, service) = helper();
    assert_eq!(create(&service, body(ID, LATER)).await.0, StatusCode::CREATED);
    for _ in 0..2 {
        let (status, answer) = send(&service, "DELETE", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await;
        assert_eq!((status, answer), (StatusCode::NO_CONTENT, Value::Null));
    }
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::NOT_FOUND);
    assert_eq!(send(&service, "DELETE", &format!("/v1/sandboxes/{OTHER}"), &Value::Null, TOKEN).await.0, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_new_end_time_is_kept_whether_it_is_sent_as_put_or_as_post() {
    let (_, service) = helper();
    create(&service, body(ID, LATER)).await;
    let midnight = json!({"end_at": "2026-12-31T23:00:00Z", "on_end": "pause"});
    for method in ["PUT", "POST"] {
        let (status, answer) = send(&service, method, &format!("/v1/sandboxes/{ID}/end"), &midnight, TOKEN).await;
        assert_eq!((status, answer["end_at"].clone(), answer["on_end"].clone()), (StatusCode::OK, json!("2026-12-31T23:00:00Z"), json!("pause")), "{method}");
    }
    let (status, answer) = send(&service, "PUT", &format!("/v1/sandboxes/{ID}/end"), &json!({"end_at": "tonight"}), TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_REQUEST, json!("invalid_input")));
}

#[tokio::test]
async fn the_end_time_takes_the_sandbox_out_by_itself_and_says_why() {
    let (sandboxes, service) = helper();
    let soon = super::time::iso8601(super::time::now() + 30);
    assert_eq!(create(&service, body(ID, &soon)).await.0, StatusCode::CREATED);
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::OK, "half a minute before its time it is still there");
    let now = json!({"end_at": super::time::iso8601(super::time::now()), "on_end": "kill"});
    assert_eq!(send(&service, "PUT", &format!("/v1/sandboxes/{ID}/end"), &now, TOKEN).await.0, StatusCode::OK);
    sandboxes.sweep();
    assert_eq!(send(&service, "GET", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await.0, StatusCode::NOT_FOUND);
    let (status, events) = send(&service, "GET", "/v1/sandbox-events?after=0", &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    let ended = &events["events"][1];
    assert_eq!((&ended["kind"], &ended["reason"], &ended["id"]), (&json!("ended"), &json!("timeout"), &json!(ID)));
    assert_eq!(events["last"], json!(2));
}

#[tokio::test]
async fn the_events_are_read_after_a_number_and_a_root_too_far_behind_is_told_so() {
    let (_, service) = helper();
    create(&service, body(ID, LATER)).await;
    send(&service, "DELETE", &format!("/v1/sandboxes/{ID}"), &Value::Null, TOKEN).await;
    let (status, answer) = send(&service, "GET", "/v1/sandbox-events?after=1", &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!((answer["events"].as_array().unwrap().len(), answer["last"].clone()), (1, json!(2)));
    assert_eq!(answer["events"][0]["reason"], "deleted");
    let (status, answer) = send(&service, "GET", "/v1/sandbox-events?after=2&limit=1", &Value::Null, TOKEN).await;
    assert_eq!((status, answer["events"].as_array().unwrap().len()), (StatusCode::OK, 0));
    for bad in ["/v1/sandbox-events", "/v1/sandbox-events?after=x", "/v1/sandbox-events?after=0&limit=0", "/v1/sandbox-events?after=0&limit=1001", "/v1/sandbox-events?after=0&x=1"] {
        let (status, answer) = send(&service, "GET", bad, &Value::Null, TOKEN).await;
        assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_REQUEST, json!("invalid_input")), "{bad}");
    }
}

#[tokio::test]
async fn the_templates_and_the_metrics_answer_with_the_contract_shape() {
    let (_, service) = helper();
    create(&service, body(ID, LATER)).await;
    let (status, answer) = send(&service, "GET", "/v1/sandbox-templates", &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(answer["templates"][0]["state"], "ready");
    assert_eq!(answer["templates"][0]["id"], "base");
    assert!(answer["templates"][0]["built_at"].as_str().is_some_and(|time| time.ends_with('Z')));
    assert!(answer["templates"][0]["size_mb"].is_number());
    let (status, answer) = send(&service, "GET", &format!("/v1/sandboxes/{ID}/metrics"), &Value::Null, TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    let sample = &answer["samples"][0];
    assert_eq!((&sample["cpu_count"], &sample["mem_total_mb"], &sample["disk_total_mb"]), (&json!(2), &json!(512), &json!(1024)));
    assert!(sample["at"].as_str().is_some_and(|time| time.ends_with('Z')));
}

#[tokio::test]
async fn the_way_into_a_sandbox_says_plainly_that_there_is_no_network_yet() {
    let (_, service) = helper();
    create(&service, body(ID, LATER)).await;
    for method in ["GET", "POST", "PUT", "PATCH", "DELETE"] {
        let (status, answer) = send_port(&service, method, &format!("/v1/sandboxes/{ID}/ports/8080/index.html"), TOKEN).await;
        assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::NOT_IMPLEMENTED, json!("no_port_proxy")), "{method}");
    }
    // The port route is the one route that does not take the bearer token: the caller's own Authorization must reach the program.
    let (status, answer) = send(&service, "GET", &format!("/v1/sandboxes/{ID}/ports/8080/index.html"), &Value::Null, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::UNAUTHORIZED, json!("unauthorized")), "bearer alone is refused here");
    let (status, answer) = send_port(&service, "GET", &format!("/v1/sandboxes/{OTHER}/ports/8080/index.html"), TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_GATEWAY, json!("not_found")), "E2B's SDKs read a 502 as not running");
}

// ---- the store and the engine, without HTTP

#[tokio::test]
async fn a_sandbox_that_ran_out_of_time_is_stopped_in_the_engine_too() {
    let engine = Arc::new(SimulatedSandboxEngine::new(limits()));
    let sandboxes = Sandboxes::new(Some(engine.clone()));
    let soon = super::time::iso8601(super::time::now() + 1);
    assert!(sandboxes.create(body(ID, &soon).to_string().as_bytes()).is_ok());
    assert_eq!(engine.running(), [ID]);
    let deadline = Instant::now() + Duration::from_secs(10);
    while sandboxes.get(ID).is_ok() && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(50));
    }
    sandboxes.sweep();
    assert!(engine.running().is_empty(), "the engine was told to stop it, not only the record");
    assert_eq!(sandboxes.list().ok().unwrap().len(), 0);
}

#[tokio::test]
async fn a_gone_sandbox_is_still_one_this_helper_had() {
    let (sandboxes, _) = helper();
    assert!(sandboxes.delete(OTHER).is_err(), "never here");
    assert!(sandboxes.create(body(ID, LATER).to_string().as_bytes()).is_ok());
    assert!(sandboxes.delete(ID).is_ok());
    assert!(sandboxes.delete(ID).is_ok(), "a second delete is answered the same way");
    assert_eq!(Refusal::NotFound, sandboxes.get(ID).unwrap_err());
    assert_eq!(sandboxes.set_end(ID, br#"{"end_at":"2027-01-01T00:00:00Z","on_end":"kill"}"#).unwrap_err(), Refusal::NotFound);
}

#[test]
fn the_contract_words_are_the_ones_the_store_writes() {
    assert_eq!(serde_json::to_value(OnEnd::Pause).unwrap(), json!("pause"));
    assert_eq!(serde_json::to_value(super::store::EventKind::Ended).unwrap(), json!("ended"));
    assert_eq!(serde_json::to_value(super::store::EndReason::Timeout).unwrap(), json!("timeout"));
}
