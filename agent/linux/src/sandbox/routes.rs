//! The sandbox routes of contract/openapi.yaml, wired onto axum in http.rs. The bearer token is checked before any of these, like every other route.
//!
//! One place decides what each refusal looks like: 404 for an unknown id (and for a helper that cannot run sandboxes at all), 400 for a body the contract
//! does not allow, 409 with the numbers for one the machine cannot take, 409 `not_pausable` for an engine that cannot stop a guest where it is, 410 for
//! events that are no longer kept, and 501 for the way into a sandbox, which this slice cannot do yet. The engine's own reason never reaches the Root: it
//! can name paths, and it goes to the helper's log only.
use super::{Refusal, EVENTS_PER_READ};
use crate::http::{error, small_body, App};
use axum::extract::{Path, RawQuery, Request, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};
use std::sync::Arc;

/// The largest `limit` the contract allows on the events route.
const MAX_EVENTS_PER_READ: usize = 1000;

pub async fn list(State(app): State<Arc<App>>) -> Response {
    answer(app.sandboxes.list().map(|sandboxes| json!({ "sandboxes": sandboxes })))
}

pub async fn create(State(app): State<Arc<App>>, request: Request) -> Response {
    let body = match small_body(request).await {
        Ok(body) => body,
        Err(reply) => return reply,
    };
    match app.sandboxes.create(&body) {
        Ok(made) if made.made => (StatusCode::CREATED, Json(made.sandbox)).into_response(),
        Ok(made) => (StatusCode::OK, Json(made.sandbox)).into_response(),
        Err(refusal) => answer::<Value>(Err(refusal)),
    }
}

pub async fn get(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    answer(app.sandboxes.get(&id))
}

pub async fn delete(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    match app.sandboxes.delete(&id) {
        Ok(()) => StatusCode::NO_CONTENT.into_response(),
        Err(refusal) => answer::<Value>(Err(refusal)),
    }
}

/// `PUT` (the Root's verb) and `POST`, which answers the same thing.
pub async fn set_end(State(app): State<Arc<App>>, Path(id): Path<String>, request: Request) -> Response {
    let body = match small_body(request).await {
        Ok(body) => body,
        Err(reply) => return reply,
    };
    answer(app.sandboxes.set_end(&id, &body))
}

pub async fn metrics(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    answer(app.sandboxes.metrics(&id).map(|samples| json!({ "samples": samples })))
}

/// `PUT /v1/sandboxes/{id}/pause`: the sandbox stopped where it is, memory and all, with its end time unchanged.
pub async fn pause(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    answer(app.sandboxes.pause(&id))
}

/// `PUT /v1/sandboxes/{id}/resume`: it carries on from where it stopped.
pub async fn resume(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    answer(app.sandboxes.resume(&id))
}

pub async fn templates(State(app): State<Arc<App>>) -> Response {
    answer(app.sandboxes.templates().map(|templates| json!({ "templates": templates.iter().map(template_json).collect::<Vec<_>>() })))
}

pub async fn events(State(app): State<Arc<App>>, RawQuery(query): RawQuery) -> Response {
    let (after, limit) = match read_events_query(query.as_deref()) {
        Ok(read) => read,
        Err(message) => return error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    };
    answer(app.sandboxes.events(after, limit).map(|(events, last)| json!({ "events": events, "last": last })))
}

/// The way into a sandbox: `/v1/sandboxes/{id}/ports/{port}/{path}`, for every method a program inside may take. The port and the path are matched here
/// so the route has exactly the shape the contract gives it; they go unused until the Firecracker engine has a network to carry them.
pub async fn ports(State(app): State<Arc<App>>, Path((id, _port, _path)): Path<(String, u16, String)>) -> Response {
    if let Err(refusal) = app.sandboxes.get(&id) {
        return port_refusal(&refusal);
    }
    answer::<Value>(Err(Refusal::NoPortProxy))
}

fn template_json(template: &super::Template) -> Value {
    json!({
        "id": template.id,
        "build": template.build,
        "state": template.state,
        "built_at": template.built_at.map(super::time::iso8601),
        "size_mb": template.size_mb,
        "message": template.message,
    })
}

/// `after` is the only required query value; `limit` is how many the Root wants at most.
fn read_events_query(query: Option<&str>) -> Result<(u64, usize), String> {
    let mut after = None;
    let mut limit = EVENTS_PER_READ;
    for pair in query.unwrap_or_default().split('&').filter(|pair| !pair.is_empty()) {
        let (name, value) = pair.split_once('=').unwrap_or((pair, ""));
        match name {
            "after" => after = Some(value.parse::<u64>().map_err(|_| "after must be a whole number, 0 or more".to_string())?),
            "limit" => limit = value.parse::<usize>().ok().filter(|sent| (1..=MAX_EVENTS_PER_READ).contains(sent)).ok_or("limit must be 1 to 1000")?,
            other => return Err(format!("unknown query {other}")),
        }
    }
    Ok((after.ok_or("after is needed: the number of the last event you saw")?, limit))
}

/// A refusal on the way into a sandbox is a 502, because E2B's SDKs read a 502 from the daemon's `/health` as "not running".
fn port_refusal(refusal: &Refusal) -> Response {
    match refusal {
        Refusal::NotFound | Refusal::NoEngine => error(StatusCode::BAD_GATEWAY, "not_found", "no such sandbox on this machine"),
        other => answer::<Value>(Err(other.clone())),
    }
}

/// The finished reply for an answer or a refusal.
fn answer<T: serde::Serialize>(result: Result<T, Refusal>) -> Response {
    match result {
        Ok(value) => Json(value).into_response(),
        Err(Refusal::NoEngine) | Err(Refusal::NotFound) => error(StatusCode::NOT_FOUND, "not_found", "no such thing"),
        Err(Refusal::Invalid(message)) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
        Err(Refusal::IdTaken) => {
            (StatusCode::CONFLICT, Json(json!({"error": {"code": "id_taken", "message": "this id was used before, for another sandbox"}}))).into_response()
        }
        Err(Refusal::TemplateNotReady(template)) => {
            (StatusCode::CONFLICT, Json(json!({"error": {"code": "template_not_ready", "message": format!("this machine has no ready template called {template}")}}))).into_response()
        }
        Err(Refusal::Room { message, resource, needed, free }) => {
            (StatusCode::CONFLICT, Json(json!({"error": {"code": "not_enough_room", "message": message, "resource": resource, "needed": needed, "free": free}}))).into_response()
        }
        Err(Refusal::TooOld) => error(StatusCode::GONE, "too_old", "those events are no longer kept; ask again from 0"),
        Err(Refusal::NoPortProxy) => error(StatusCode::NOT_IMPLEMENTED, "no_port_proxy", "this helper cannot pass a request into a sandbox yet: it has no network for one"),
        Err(Refusal::NotPausable(cause)) => {
            eprintln!("sandbox: the engine cannot pause or resume it: {cause}");
            (StatusCode::CONFLICT, Json(json!({"error": {"code": "not_pausable", "message": "this sandbox cannot be paused or resumed on this machine"}}))).into_response()
        }
        Err(Refusal::Engine(cause)) => {
            eprintln!("sandbox: the engine failed: {cause}");
            error(StatusCode::INTERNAL_SERVER_ERROR, "internal", "internal error")
        }
    }
}
