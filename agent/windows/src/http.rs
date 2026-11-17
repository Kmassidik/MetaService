//! The helper API for Windows, thin v1: health, facts, stats, host terminal, leave. The routes and
//! answer shapes mirror the Linux helper's (`agent/linux/src/http.rs`); what is gone is everything
//! that needs the VM engine, sandboxes, storage walk, security log or chat bundle, because Windows
//! v1 does none of those. The auth rule is the same: bearer token, constant-time compare, a short
//! lockout when one address keeps sending bad tokens.
use crate::engine_windows::WindowsEngine;
use crate::hardware::Hardware;
use crate::models::Gpu;
use crate::platform;
use axum::extract::{State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get};
use axum::Json;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use subtle::ConstantTimeEq;

const MAX_BODY_BYTES: usize = 64 * 1024;
const BAD_TOKEN_WINDOW: Duration = Duration::from_secs(60);

pub struct App {
    /// The specs and the engine, assembled once at start. The engine is the Windows one: no VMs.
    pub specs: StaticSpecs,
    pub token: String,
    pub bad_token_limit: u32,
    pub state_dir: Option<std::path::PathBuf>,
    parent: Mutex<Option<(String, String)>>,
    bad: Mutex<HashMap<IpAddr, (u32, Instant)>>,
    space: crate::budget::SpaceBudget,
}

impl App {
    pub fn new(specs: StaticSpecs, token: String, bad_token_limit: u32, state_dir: Option<std::path::PathBuf>, space: crate::budget::SpaceBudget) -> Arc<App> {
        Arc::new(App { specs, token, bad_token_limit, state_dir, parent: Mutex::new(None), bad: Mutex::new(HashMap::new()), space })
    }

    /// Where the parent is and the token this helper reports with: what "Update helper" downloads the new build with.
    pub fn set_parent(&self, root: String, token: String) {
        *self.parent.lock().unwrap() = Some((root, token));
    }
}

pub fn router(app: Arc<App>) -> axum::Router {
    axum::Router::new()
        .route("/v1/health", get(health))
        .route("/v1/facts", get(facts_route))
        .route("/v1/stats", get(stats_route))
        .route("/v1/host-terminal", get(crate::conpty::host_terminal))
        .route("/v1/workloads", get(list).post(create))
        .route("/v1/workloads/:id/terminal", get(vm_terminal_refused))
        .with_state(app)
}

async fn health(State(_app): State<Arc<App>>) -> Response {
    Json(json!({ "status": "ok", "agent_version": crate::config::VERSION, "contract_version": platform::CONTRACT_VERSION, "bundle_version": Value::Null })).into_response()
}

/// The machine's facts, the same shape as the Linux helper's: the panel's cards read these.
async fn facts_route(State(app): State<Arc<App>>) -> Response {
    let reading = crate::facts::read_machine();
    let (ram_total_mb, disk_total_gb, disk_available_gb) = reading
        .map(|r| (r.ram_total_mb, r.disk_total_gb, r.disk_available_gb))
        .unwrap_or((app.space.ram_total_mb, app.space.disk_total_gb, 1));
    let engine_info = json!({"name": crate::engine_windows::NONE_ENGINE, "version": Value::Null, "ready": false});
    let body = json!({
        "os": "windows",
        "arch": std::env::consts::ARCH,
        "cpu_cores": app.specs.cpu_cores,
        "cpu_model": app.specs.cpu_model,
        "ram_total_mb": ram_total_mb,
        "disk_total_gb": disk_total_gb,
        "free_ram_mb": ram_total_mb.saturating_sub(app.space.reserve_ram_mb),
        "free_disk_gb": disk_available_gb,
        "gpu": app.specs.gpu,
        "hardware": app.specs.hardware,
        "capabilities": {"vm": false, "container": false, "gpu_in_vm": false, "gpu_in_container": false},
        "problems": [],
        "agent_version": crate::config::VERSION,
        "engine": engine_info,
        "agent_build": crate::build::running().unwrap_or_default(),
    });
    Json(body).into_response()
}

async fn stats_route(State(_app): State<Arc<App>>) -> Response {
    let reading = crate::facts::read_machine();
    let cpu = std::thread::available_parallelism().map(|n| n.get() as u32).unwrap_or(1);
    let body = json!({
        "cpu": {"cores": cpu},
        "ram": {"total_mb": reading.as_ref().map(|r| r.ram_total_mb).unwrap_or(0), "free_mb": reading.as_ref().map(|r| r.disk_available_gb).unwrap_or(0)},
    });
    Json(body).into_response()
}

async fn list(State(app): State<Arc<App>>) -> Response {
    let _ = &app;
    Json(json!([])).into_response()
}

/// VM creation on Windows: refused with a plain message. The engine refuses too; this route answers
/// before the engine is reached so the message never depends on engine internals.
async fn create(State(app): State<Arc<App>>, headers: HeaderMap, body: axum::body::Bytes) -> Response {
    let _ = (app, headers);
    if body.len() > MAX_BODY_BYTES {
        return error(StatusCode::BAD_REQUEST, "invalid_input", "the request is too large");
    }
    error(StatusCode::CONFLICT, "vm_not_supported", crate::engine_windows::VM_MESSAGE)
}

/// The VM console on Windows: refused with the same plain message (the host terminal has its own route).
async fn vm_terminal_refused() -> Response {
    error(StatusCode::CONFLICT, "vm_not_supported", crate::engine_windows::VM_MESSAGE)
}

pub fn error(status: StatusCode, code: &str, message: &str) -> Response {
    (status, Json(json!({"error": {"code": code, "message": message}}))).into_response()
}

/// The bearer-token middleware, as on Linux: constant-time compare, lockout for a bad address.
pub async fn require_token(State(app): State<Arc<App>>, headers: HeaderMap, ConnectInfo(peer): ConnectInfo<SocketAddrInfo>, request: Request, next: Next) -> Response {
    let sent = headers.get(axum::http::header::AUTHORIZATION).and_then(|v| v.to_str().ok()).and_then(|v| v.strip_prefix("Bearer ")).unwrap_or("");
    if constant_time_eq(sent, &app.token) {
        return next.run(request).await;
    }
    let mut bad = app.bad.lock().unwrap();
    let now = Instant::now();
    let (count, first) = bad.entry(peer.ip()).or_insert((0, now));
    if now.duration_since(*first) > BAD_TOKEN_WINDOW {
        *count = 0;
        *first = now;
    }
    *count += 1;
    if *count >= app.bad_token_limit {
        return error(StatusCode::TOO_MANY_REQUESTS, "rate_limited", "too many bad tokens from this address; wait a minute");
    }
    drop(bad);
    error(StatusCode::UNAUTHORIZED, "unauthorized", "the token does not match")
}

type SocketAddrInfo = std::net::SocketAddr;

use axum::middleware::Next;
use axum::extract::{Request, ConnectInfo};

fn constant_time_eq(left: &str, right: &str) -> bool {
    left.as_bytes().ct_eq(right.as_bytes()).into()
}

/// The specs that never change while the helper runs: measured once at start.
#[derive(Clone)]
pub struct StaticSpecs {
    pub cpu_cores: u32,
    pub cpu_model: Option<String>,
    pub gpu: Vec<Gpu>,
    pub hardware: Option<Hardware>,
}
