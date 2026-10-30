//! Admin listener (CONTRACT section 5): the page, and the key-protected API.
use crate::approval::{self, ApproveRequest};
use crate::clock::iso8601;
use crate::codes::new_link_id;
use crate::constants::{BODY_LIMIT_BYTES, LIFETIME_SECS};
use crate::crypto::secure_eq;
use crate::error::ApiError;
use crate::state::Shared;
use crate::store::{Link, Pending};
use crate::supported;
use axum::extract::rejection::JsonRejection;
use axum::extract::{DefaultBodyLimit, Path, Request, State};
use axum::http::{header, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;

const ADMIN_KEY_HEADER: &str = "x-admin-key";
const KEY_PREFIX_LEN: usize = 8;
const INDEX_HTML: &str = include_str!("../../web/index.html");
const APP_JS: &str = include_str!("../../web/app.js");
const STYLE_CSS: &str = include_str!("../../web/style.css");

pub fn router(state: Shared) -> Router<()> {
    let api = Router::new()
        .route("/admin/links", post(create_link))
        .route("/admin/supported", get(supported_table))
        .route("/admin/pending", get(list_pending))
        .route("/admin/pending/:id/approve", post(approve))
        .route("/admin/pending/:id/refuse", post(refuse))
        .route("/admin/peers", get(list_peers))
        .route("/admin/peers/:name", delete(remove_peer))
        .route_layer(middleware::from_fn_with_state(state.clone(), require_key));
    // The page and its two static files carry no secret; the page asks for the key itself.
    let pages = Router::new()
        .route("/", get(|| async { static_file("text/html; charset=utf-8", INDEX_HTML) }))
        .route("/app.js", get(|| async { static_file("text/javascript; charset=utf-8", APP_JS) }))
        .route("/style.css", get(|| async { static_file("text/css; charset=utf-8", STYLE_CSS) }));
    pages.merge(api).layer(DefaultBodyLimit::max(BODY_LIMIT_BYTES)).with_state(state)
}

fn static_file(content_type: &'static str, body: &'static str) -> Response {
    ([(header::CONTENT_TYPE, content_type)], body).into_response()
}

async fn require_key(State(state): State<Shared>, req: Request, next: Next) -> Response {
    let given = req.headers().get(ADMIN_KEY_HEADER).and_then(|v| v.to_str().ok()).unwrap_or("");
    if !secure_eq(given, &state.admin_key) {
        return ApiError::new(StatusCode::UNAUTHORIZED, "unauthorized").into_response();
    }
    next.run(req).await
}

fn body_of<T>(body: Result<Json<T>, JsonRejection>) -> Result<T, ApiError> {
    body.map(|Json(v)| v).map_err(|r| ApiError::new(r.status(), "bad_request"))
}

#[derive(Deserialize)]
struct NewLink {
    os: String,
    cpu: String,
}

async fn create_link(State(state): State<Shared>, body: Result<Json<NewLink>, JsonRejection>) -> Result<Json<Value>, ApiError> {
    let NewLink { os, cpu } = body_of(body)?;
    supported::check_pair(&state.config.builds, &os, &cpu).map_err(|p| ApiError::bad(p.code).with("reason", p.reason))?;
    let now = state.now();
    let link = Link { id: new_link_id(), os, cpu, created_at: now, expires_at: now + LIFETIME_SECS, used_at: None };
    state.store.insert_link(&link)?;
    let command = format!("curl -fsSL \"{}/j/{}?os={}&cpu={}\" | sh", state.config.public_url, link.id, link.os, link.cpu);
    Ok(Json(json!({ "link": link.id, "expires_at": iso8601(link.expires_at), "command": command })))
}

async fn supported_table(State(state): State<Shared>) -> Json<Value> {
    Json(supported::table(&state.config.builds))
}

/// Never includes the code (only its hash is stored).
fn pending_json(p: &Pending) -> Value {
    json!({
        "id": p.id, "hostname": p.hostname, "os": p.os, "cpu": p.cpu,
        "share": { "cores": p.ask.cores, "ram_mb": p.ask.ram_mb, "disk_gb": p.ask.disk_gb },
        "created_at": iso8601(p.created_at), "expires_at": iso8601(p.expires_at), "tries_left": p.tries_left,
    })
}

async fn list_pending(State(state): State<Shared>) -> Result<Json<Value>, ApiError> {
    let open = state.store.list_open_pending(state.now())?;
    Ok(Json(Value::Array(open.iter().map(pending_json).collect())))
}

async fn approve(
    State(state): State<Shared>,
    Path(id): Path<String>,
    body: Result<Json<ApproveRequest>, JsonRejection>,
) -> Result<Json<Value>, ApiError> {
    let address = approval::approve(&state, &id, body_of(body)?)?;
    Ok(Json(json!({ "address": address.to_string() })))
}

async fn refuse(State(state): State<Shared>, Path(id): Path<String>) -> Result<Json<Value>, ApiError> {
    if !state.store.refuse_pending(&id)? {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "unknown_pending"));
    }
    Ok(Json(json!({ "state": "refused" })))
}

/// Handshake times by public key; when WireGuard cannot be asked, the list still works.
fn handshakes(state: &Shared) -> HashMap<String, i64> {
    match state.wg.show() {
        Ok(stats) => stats.into_iter().map(|s| (s.public_key, s.last_handshake)).collect(),
        Err(reason) => {
            eprintln!("join-share: show failed: {reason}");
            HashMap::new()
        }
    }
}

async fn list_peers(State(state): State<Shared>) -> Result<Json<Value>, ApiError> {
    let seen = handshakes(&state);
    let now = state.now();
    let rows: Vec<Value> = state
        .store
        .list_peers()?
        .iter()
        .map(|p| {
            let ago = seen.get(&p.public_key).filter(|at| **at > 0).map(|at| now - at);
            json!({
                "name": p.name, "address": p.address, "public_key": p.public_key.chars().take(KEY_PREFIX_LEN).collect::<String>(),
                "os": p.os, "cpu": p.cpu, "last_handshake_secs_ago": ago,
            })
        })
        .collect();
    Ok(Json(Value::Array(rows)))
}

async fn remove_peer(State(state): State<Shared>, Path(name): Path<String>) -> Result<Json<Value>, ApiError> {
    approval::remove_peer(&state, &name)?;
    Ok(Json(json!({ "removed": name })))
}
