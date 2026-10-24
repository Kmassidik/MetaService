//! The route and the engines: status codes, the 502 body, the simulated installed set, and the exact Incus call (a recording runner).
use super::script::{HERMES_SCRIPT, OPENCLAW_SCRIPT};
use super::simulated::{SimulatedApp, SIMULATED_SHA256, SIMULATED_VERSION};
use super::report::AppFailure;
use super::{incus_call, INSTALL_TIMEOUT};
use crate::cpu::CpuOffer;
use crate::incus::{IncusEngine, Runner};
use crate::models::*;
use crate::ssh_keys_tests::{machine, send, service_over, TOKEN};
use axum::http::StatusCode;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

const PATH_APP: &str = "/v1/workloads/w-1/app";
const OPENCLAW_BODY: &str = r#"{"app":"openclaw"}"#;
const HERMES_BODY: &str = r#"{"app":"hermes"}"#;

fn done(app: &str, installed: bool, sha: Value) -> Value {
    json!({"app": app, "installed": installed, "version": SIMULATED_VERSION, "installer_sha256": sha})
}

#[tokio::test]
async fn a_fresh_install_answers_200_and_a_second_one_changes_nothing() {
    let (engine, service) = machine();
    let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, done("openclaw", true, json!(SIMULATED_SHA256))));
    let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, done("openclaw", false, Value::Null)));
    assert!(engine.apps.is_installed("w-1", super::App::Openclaw));
    assert!(!engine.apps.is_installed("w-1", super::App::Hermes), "the other app is separate");
    let (_, answer) = send(&service, "PUT", PATH_APP, HERMES_BODY, TOKEN).await;
    assert_eq!(answer, done("hermes", true, json!(SIMULATED_SHA256)));
}

#[tokio::test]
async fn every_bad_body_is_a_400_invalid_input() {
    let (_, service) = machine();
    for body in [r#"{"app":"nginx"}"#, r#"{"app":7}"#, r#"{"app":"hermes","extra":1}"#, "{}", "nope"] {
        let (status, answer) = send(&service, "PUT", PATH_APP, body, TOKEN).await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
        assert_eq!(answer["error"]["code"], "invalid_input");
    }
}

#[tokio::test]
async fn a_wrong_token_is_401_an_unknown_vm_404_and_a_stopped_vm_409() {
    let (engine, service) = machine();
    let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, "wrong").await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::UNAUTHORIZED, json!("unauthorized")));
    let (status, answer) = send(&service, "PUT", "/v1/workloads/w-9/app", OPENCLAW_BODY, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::NOT_FOUND, json!("not_found")));
    let (status, _) = send(&service, "PUT", "/v1/workloads/bad%20id/app", OPENCLAW_BODY, TOKEN).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    crate::engine::Engine::set_running(engine.as_ref(), "w-1", false).ok().unwrap();
    let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::CONFLICT, json!("not_running")));
    assert!(!engine.apps.is_installed("w-1", super::App::Openclaw), "nothing ran in a stopped VM");
}

#[tokio::test]
async fn a_failed_install_is_502_with_plain_words_and_a_short_log_tail() {
    let (engine, service) = machine();
    engine.apps.set_behaviour(SimulatedApp::Fails(AppFailure::DownloadFailed));
    let (status, answer) = send(&service, "PUT", PATH_APP, HERMES_BODY, TOKEN).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY);
    assert_eq!(answer["error"]["code"], "app_install_failed");
    assert_eq!(answer["error"]["message"], "The VM could not download the installer. Check that the VM has internet access.");
    assert_eq!(answer["error"]["log_tail"], json!(["simulated installer output"]));
    assert!(!engine.apps.is_installed("w-1", super::App::Hermes));
}

#[tokio::test]
async fn every_failure_code_is_a_502() {
    for failure in [AppFailure::NoPackageManager, AppFailure::PrerequisitesFailed, AppFailure::DownloadFailed, AppFailure::InstallFailed] {
        let (engine, service) = machine();
        engine.apps.set_behaviour(SimulatedApp::Fails(failure));
        let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, TOKEN).await;
        assert_eq!((status, answer["error"]["message"].clone()), (StatusCode::BAD_GATEWAY, json!(failure.message())));
    }
}

#[tokio::test]
async fn an_unreadable_report_is_a_502_too() {
    let (engine, service) = machine();
    engine.apps.set_behaviour(SimulatedApp::Garbage);
    let (status, answer) = send(&service, "PUT", PATH_APP, OPENCLAW_BODY, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_GATEWAY, json!("app_install_failed")));
    assert_eq!(answer["error"]["log_tail"], json!(["something else entirely"]));
}

#[tokio::test]
async fn a_slow_install_still_works_and_the_time_limit_is_twenty_minutes() {
    let (engine, service) = machine();
    engine.apps.set_behaviour(SimulatedApp::Delay(Duration::from_millis(200)));
    let (status, answer) = send(&service, "PUT", PATH_APP, HERMES_BODY, TOKEN).await;
    assert_eq!((status, answer["installed"].clone()), (StatusCode::OK, json!(true)));
    assert_eq!(INSTALL_TIMEOUT, Duration::from_secs(1200));
}

// ---- the Incus engine

struct Recording {
    calls: Mutex<Vec<(Vec<String>, Vec<u8>, Duration)>>,
    answer: Result<String, String>,
}

impl Runner for Recording {
    fn run(&self, _arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        let instance = json!([{"name": "ms-w-1", "status": "Running", "config": {"user.metaservice.id": "w-1", "user.metaservice.name": "box", "user.metaservice.kind": "vm",
            "user.metaservice.cpu": "1", "user.metaservice.ram_mb": "512", "user.metaservice.disk_gb": "1"}, "state": null}]);
        Ok(instance.to_string())
    }

    fn run_with_input(&self, arguments: &[String], input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push((arguments.to_vec(), input.to_vec(), timeout));
        self.answer.clone().map_err(EngineError::Failed)
    }
}

fn over(answer: Result<String, String>) -> (Arc<Recording>, Arc<crate::service::Service>) {
    let runner = Arc::new(Recording { calls: Mutex::new(Vec::new()), answer });
    let capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY, sandbox: false };
    (runner.clone(), service_over(Arc::new(IncusEngine::new(runner, capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1))))
}

#[tokio::test]
async fn incus_runs_one_constant_script_on_standard_input_with_no_request_data_in_argv() {
    let (runner, service) = over(Ok("m\n".into()));
    for (body, script) in [(OPENCLAW_BODY, OPENCLAW_SCRIPT), (HERMES_BODY, HERMES_SCRIPT)] {
        send(&service, "PUT", PATH_APP, body, TOKEN).await;
        let calls = runner.calls.lock().unwrap();
        let (arguments, input, timeout) = calls.last().unwrap().clone();
        assert_eq!(arguments, incus_call("ms-w-1"));
        assert_eq!(input, script.as_bytes());
        assert_eq!(timeout, Duration::from_secs(1200));
    }
}

#[tokio::test]
async fn incus_turns_the_script_output_into_the_answer_and_a_broken_call_into_a_502() {
    let output = format!("fetching\n{}\napp=hermes\ninstalled=true\nversion=1.0\nsha256={SIMULATED_SHA256}\n", super::script::RESULT_MARKER);
    let (_, service) = over(Ok(output));
    let (status, answer) = send(&service, "PUT", PATH_APP, HERMES_BODY, TOKEN).await;
    assert_eq!((status, answer), (StatusCode::OK, json!({"app": "hermes", "installed": true, "version": "1.0", "installer_sha256": SIMULATED_SHA256})));
    let (_, service) = over(Err("engine-detail-xyz".into()));
    let (status, answer) = send(&service, "PUT", PATH_APP, HERMES_BODY, TOKEN).await;
    assert_eq!((status, answer["error"]["code"].clone()), (StatusCode::BAD_GATEWAY, json!("app_install_failed")));
    assert_eq!(answer["error"]["log_tail"], json!([]));
    assert!(!answer.to_string().contains("engine-detail-xyz"), "the engine's own text stays out of the answer");
}

#[tokio::test]
async fn the_images_list_has_the_two_apps_ready() {
    let (_, service) = machine();
    let (status, answer) = send(&service, "GET", "/v1/images", "", TOKEN).await;
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<&str> = answer["images"].as_array().unwrap().iter().map(|entry| entry["id"].as_str().unwrap()).collect();
    assert_eq!(ids, ["blank", "openclaw", "hermes"]);
}
