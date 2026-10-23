//! The create route with CPU settings: a setting this machine does not offer is a 400 in plain words and makes nothing, one it offers is made.
//! Uses the simulated engine, so nothing real is touched.
use crate::cpu::{CpuOffer, CpuVendor, NO_FLAG_MESSAGE, NO_MODEL_MESSAGE, NO_SOCKETS_MESSAGE};
use crate::engine::{default_capabilities, SimulatedEngine};
use crate::models::*;
use crate::service::Service;
use crate::ssh_keys_tests::{send, service_over, TOKEN};
use axum::http::StatusCode;
use serde_json::{json, Value};
use std::sync::Arc;

fn machine(cpu: CpuOffer) -> Arc<Service> {
    service_over(Arc::new(SimulatedEngine::new(Capabilities { cpu, ..default_capabilities() })))
}

fn create_body(command_id: &str, kind: &str, settings: Value) -> String {
    let mut body = json!({"command_id": command_id, "name": "box", "kind": kind, "cpu": 4, "ram_mb": 2048, "disk_gb": 10});
    body.as_object_mut().unwrap().extend(settings.as_object().unwrap().clone());
    body.to_string()
}

#[tokio::test]
async fn a_setting_this_machine_does_not_offer_is_a_400_in_plain_words_and_makes_nothing() {
    let service = machine(CpuOffer::HOST_ONLY);
    for (settings, message) in [
        (json!({"cpu_type": "EPYC-Genoa"}), NO_MODEL_MESSAGE), (json!({"cpu_sockets": 2}), NO_SOCKETS_MESSAGE), (json!({"cpu_sockets": 1}), NO_SOCKETS_MESSAGE),
        (json!({"cpu_flags": {"aes": "on"}}), NO_FLAG_MESSAGE),
    ] {
        let (status, answer) = send(&service, "POST", "/v1/workloads", &create_body("c-1", "vm", settings.clone()), TOKEN).await;
        assert_eq!((status, &answer["error"]["code"], &answer["error"]["message"]), (StatusCode::BAD_REQUEST, &json!("invalid_input"), &json!(message)), "{settings}");
    }
    let (status, answer) = send(&service, "POST", "/v1/workloads", &create_body("c-1", "container", json!({"cpu_type": "host"})), TOKEN).await;
    assert_eq!((status, &answer["error"]["code"]), (StatusCode::BAD_REQUEST, &json!("invalid_input")), "the wrong kind, whatever the value");
    let (_, listed) = send(&service, "GET", "/v1/workloads", "", TOKEN).await;
    assert_eq!(listed["workloads"], json!([]));
    assert!(service.command("c-1").is_none(), "a refused create is not a command");
}

#[tokio::test]
async fn a_machine_that_offers_nothing_new_still_takes_the_host_model_and_a_capped_container() {
    let service = machine(CpuOffer::HOST_ONLY);
    for body in [create_body("c-h", "vm", json!({"cpu_type": "host"})), create_body("c-c", "container", json!({"cpu_limit_percent": 150}))] {
        let (status, _) = send(&service, "POST", "/v1/workloads", &body, TOKEN).await;
        assert_eq!(status, StatusCode::ACCEPTED, "{body}");
    }
}

#[tokio::test]
async fn what_this_machine_offers_is_made_and_said_in_the_facts() {
    let service = machine(CpuOffer::new("x86_64", Some((9, 2)), true, Some(CpuVendor::Amd)));
    let vm = create_body("c-v", "vm", json!({"cpu_sockets": 2, "cpu_type": "EPYC-Genoa", "cpu_flags": {"nested-virt": "on", "aes": "off"}}));
    let (status, answer) = send(&service, "POST", "/v1/workloads", &vm, TOKEN).await;
    assert_eq!((status, &answer["state"]), (StatusCode::ACCEPTED, &json!("running")));
    let (_, facts) = send(&service, "GET", "/v1/facts", "", TOKEN).await;
    let capabilities = &facts["capabilities"];
    assert_eq!((&capabilities["cpu_topology"], &capabilities["cpu_flags"], &capabilities["cpu_limit"]), (&json!(true), &json!(["nested-virt", "aes"]), &json!(true)));
    assert_eq!(capabilities["cpu_models"][0], "host");
}
