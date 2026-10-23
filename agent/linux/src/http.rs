//! The Agent half of contract/openapi.yaml, on axum.
use crate::models::{CONTRACT_VERSION, Refusal};
use crate::service::{Failure, Service};
use crate::ssh_install;
use crate::ssh_keys::SshRequest;
use crate::stats::{wants_processes, Monitor};
use crate::validate::{is_id, BundleRequest, BundleUninstallRequest, CreateRequest};
use axum::body::Body;
use axum::extract::{ConnectInfo, Path, RawQuery, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post, put};
use axum::{Json, Router};
use rand::Rng;
use serde_json::json;
use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use subtle::ConstantTimeEq;

pub const MAX_BODY_BYTES: usize = 64 * 1024;
const BAD_TOKEN_WINDOW: Duration = Duration::from_secs(60);

pub struct App {
    pub service: Arc<Service>,
    pub token: String,
    pub bad_token_limit: u32,
    stats: Monitor,
    bad: Mutex<HashMap<IpAddr, (u32, Instant)>>,
}

impl App {
    pub fn new(service: Arc<Service>, token: String, bad_token_limit: u32) -> Arc<App> {
        Arc::new(App { service, token, bad_token_limit, stats: Monitor::system(crate::facts::find_nvidia_smi()), bad: Mutex::new(HashMap::new()) })
    }

    fn locked_out(&self, ip: IpAddr) -> bool {
        let bad = self.bad.lock().unwrap();
        bad.get(&ip).is_some_and(|(count, since)| since.elapsed() < BAD_TOKEN_WINDOW && *count >= self.bad_token_limit)
    }

    fn count_bad(&self, ip: IpAddr) {
        let mut bad = self.bad.lock().unwrap();
        let entry = bad.entry(ip).or_insert((0, Instant::now()));
        if entry.1.elapsed() >= BAD_TOKEN_WINDOW {
            *entry = (0, Instant::now());
        }
        entry.0 += 1;
    }
}

pub fn router(app: Arc<App>) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/facts", get(facts))
        .route("/v1/stats", get(stats))
        .route("/v1/images", get(images))
        .route("/v1/workloads", get(list).post(create))
        .route("/v1/workloads/:id/start", post(start))
        .route("/v1/workloads/:id/stop", post(stop))
        .route("/v1/workloads/:id/gpu-check", post(gpu_check))
        .route("/v1/workloads/:id/ssh-keys", put(ssh_keys))
        .route("/v1/workloads/:id/app", put(app_install))
        .route("/v1/workloads/:id", delete(remove))
        .route("/v1/bundle/install", post(install))
        .route("/v1/bundle/uninstall", post(uninstall))
        .route("/v1/commands/:id", get(command))
        .fallback(not_found)
        .layer(middleware::from_fn_with_state(app.clone(), require_token))
        .layer(middleware::from_fn(security_headers))
        .with_state(app)
}

// ---- middleware

async fn security_headers(request: Request, next: Next) -> Response {
    let mut response = next.run(request).await;
    let headers = response.headers_mut();
    headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    headers.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert("content-security-policy", HeaderValue::from_static("default-src 'none'; frame-ancestors 'none'"));
    headers.insert("x-metaservice-contract", HeaderValue::from_static(CONTRACT_VERSION));
    response
}

/// Every request needs the command token. Too many wrong ones from one address lock that address out for a minute.
async fn require_token(State(app): State<Arc<App>>, ConnectInfo(peer): ConnectInfo<SocketAddr>, request: Request, next: Next) -> Response {
    if app.locked_out(peer.ip()) {
        return error(StatusCode::TOO_MANY_REQUESTS, "rate_limited", "too many requests, try again shortly");
    }
    let sent = bearer(request.headers());
    let good = sent.is_some_and(|s| s.as_bytes().ct_eq(app.token.as_bytes()).into());
    if !good {
        app.count_bad(peer.ip());
        return error(StatusCode::UNAUTHORIZED, "unauthorized", "missing or wrong token");
    }
    next.run(request).await
}

fn bearer(headers: &HeaderMap) -> Option<&str> {
    let value = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    value.strip_prefix("Bearer ").filter(|token| value.len() <= 600 && !token.is_empty())
}

// ---- replies

fn error(status: StatusCode, code: &str, message: &str) -> Response {
    (status, Json(json!({"error": {"code": code, "message": message}}))).into_response()
}

fn refusal(r: &Refusal) -> Response {
    (StatusCode::CONFLICT, Json(json!({"error": {"code": r.code, "message": r.message, "resource": r.resource, "needed": r.needed, "free": r.free}}))).into_response()
}

fn failure(failure: Failure) -> Response {
    match failure {
        Failure::Refused(r) => refusal(&r),
        Failure::NotFound => error(StatusCode::NOT_FOUND, "not_found", "no such thing"),
        Failure::Engine(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "internal", "internal error"),
        Failure::App(failed) => (StatusCode::BAD_GATEWAY, Json(json!({"error": {"code": crate::apps::ERROR_CODE, "message": failed.message, "log_tail": failed.log_tail}}))).into_response(),
        Failure::Sshd(reason) => error(StatusCode::BAD_GATEWAY, ssh_install::ERROR_CODE, reason.message()),
    }
}

fn accepted(command: &crate::models::Command) -> Response {
    (StatusCode::ACCEPTED, Json(json!({"command_id": command.command_id, "state": command.state}))).into_response()
}

/// The body, if it is small enough. A declared length over the limit is refused without reading.
#[allow(clippy::result_large_err)] // the Err is the finished reply, sent as it is
async fn small_body(request: Request) -> Result<Vec<u8>, Response> {
    let declared = request.headers().get(header::CONTENT_LENGTH).and_then(|v| v.to_str().ok()).and_then(|v| v.parse::<usize>().ok());
    if declared.is_some_and(|n| n > MAX_BODY_BYTES) {
        return Err(error(StatusCode::PAYLOAD_TOO_LARGE, "too_large", "request body too large"));
    }
    axum::body::to_bytes(Body::new(request.into_body()), MAX_BODY_BYTES).await.map(|b| b.to_vec()).map_err(|_| error(StatusCode::PAYLOAD_TOO_LARGE, "too_large", "request body too large"))
}

/// The caller's command id (so a retry is safe), or a fresh one.
#[allow(clippy::result_large_err)]
fn command_id(headers: &HeaderMap) -> Result<String, Response> {
    let Some(sent) = headers.get("x-command-id") else {
        const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";
        let mut random = rand::thread_rng();
        return Ok(format!("cmd-{}", (0..12).map(|_| ALPHABET[random.gen_range(0..ALPHABET.len())] as char).collect::<String>()));
    };
    sent.to_str().ok().filter(|text| is_id(text)).map(str::to_string).ok_or_else(|| error(StatusCode::BAD_REQUEST, "invalid_input", "X-Command-Id is not a valid id"))
}

fn ok(value: impl serde::Serialize) -> Response {
    Json(value).into_response()
}

// ---- endpoints

async fn not_found(method: Method) -> Response {
    let _ = method;
    error(StatusCode::NOT_FOUND, "not_found", "no such path")
}

async fn health(State(app): State<Arc<App>>) -> Response {
    ok(app.service.health().await)
}

async fn facts(State(app): State<Arc<App>>) -> Response {
    app.service.facts().await.map(ok).unwrap_or_else(failure)
}

/// The machine's real state now. Reading files and running `nvidia-smi` blocks, so it runs off the async threads.
/// `?processes=0` skips the program list (and the walk through /proc that makes it); `1` or nothing keeps it; anything else is a 400.
async fn stats(State(app): State<Arc<App>>, RawQuery(query): RawQuery) -> Response {
    let with_processes = match wants_processes(query.as_deref()) {
        Ok(wanted) => wanted,
        Err(message) => return error(StatusCode::BAD_REQUEST, "invalid_input", message),
    };
    match tokio::task::spawn_blocking(move || app.stats.read(with_processes)).await {
        Ok(Ok(reading)) => ok(reading),
        Ok(Err(cause)) => {
            eprintln!("stats failed: {cause}");
            error(StatusCode::INTERNAL_SERVER_ERROR, "internal", "internal error")
        }
        Err(_) => error(StatusCode::INTERNAL_SERVER_ERROR, "internal", "internal error"),
    }
}

async fn images() -> Response {
    ok(crate::images::prepared())
}

async fn list(State(app): State<Arc<App>>) -> Response {
    app.service.workloads().await.map(|w| ok(json!({"workloads": w}))).unwrap_or_else(failure)
}

async fn create(State(app): State<Arc<App>>, request: Request) -> Response {
    let body = match small_body(request).await { Ok(body) => body, Err(reply) => return reply };
    match CreateRequest::parse(&body) {
        Ok(parsed) => app.service.create(parsed).await.map(|c| accepted(&c)).unwrap_or_else(failure),
        Err(message) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    }
}

async fn start(State(app): State<Arc<App>>, Path(id): Path<String>, headers: HeaderMap) -> Response {
    change(app, id, headers, true).await
}

async fn stop(State(app): State<Arc<App>>, Path(id): Path<String>, headers: HeaderMap) -> Response {
    change(app, id, headers, false).await
}

async fn change(app: Arc<App>, id: String, headers: HeaderMap, running: bool) -> Response {
    if !is_id(&id) {
        return failure(Failure::NotFound);
    }
    match command_id(&headers) {
        Ok(command) => app.service.set_running(&command, &id, running).await.map(|c| accepted(&c)).unwrap_or_else(failure),
        Err(reply) => reply,
    }
}

/// A read-only look inside the workload for the GPU. The id is the only input, and it is checked; no body is read.
async fn gpu_check(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    if !is_id(&id) {
        return failure(Failure::NotFound);
    }
    app.service.gpu_check(&id).await.map(ok).unwrap_or_else(failure)
}

/// The complete SSH key list for root of one workload. The body is checked again here; the keys never reach a log, an error text or a command line.
async fn ssh_keys(State(app): State<Arc<App>>, Path(id): Path<String>, request: Request) -> Response {
    if !is_id(&id) {
        return failure(Failure::NotFound);
    }
    let body = match small_body(request).await { Ok(body) => body, Err(reply) => return reply };
    match SshRequest::parse(&body) {
        Ok(request) => app.service.apply_ssh_keys(&id, request).await.map(ok).unwrap_or_else(failure),
        Err(message) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    }
}

/// Puts OpenClaw or Hermes on top of a running VM. The body is only the choice between the two constant scripts.
async fn app_install(State(app): State<Arc<App>>, Path(id): Path<String>, request: Request) -> Response {
    if !is_id(&id) {
        return failure(Failure::NotFound);
    }
    let body = match small_body(request).await { Ok(body) => body, Err(reply) => return reply };
    match crate::apps::App::parse(&body) {
        Ok(chosen) => app.service.install_app(&id, chosen).await.map(ok).unwrap_or_else(failure),
        Err(message) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    }
}

async fn remove(State(app): State<Arc<App>>, Path(id): Path<String>, headers: HeaderMap) -> Response {
    if !is_id(&id) {
        return failure(Failure::NotFound);
    }
    match command_id(&headers) {
        Ok(command) => app.service.delete(&command, &id).await.map(|c| accepted(&c)).unwrap_or_else(failure),
        Err(reply) => reply,
    }
}

async fn install(State(app): State<Arc<App>>, request: Request) -> Response {
    let body = match small_body(request).await { Ok(body) => body, Err(reply) => return reply };
    match BundleRequest::parse(&body) {
        Ok(parsed) => app.service.install_bundle(parsed).await.map(|c| accepted(&c)).unwrap_or_else(failure),
        Err(message) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    }
}

async fn uninstall(State(app): State<Arc<App>>, request: Request) -> Response {
    let body = match small_body(request).await { Ok(body) => body, Err(reply) => return reply };
    match BundleUninstallRequest::parse(&body) {
        Ok(parsed) => app.service.uninstall_bundle(parsed).await.map(|c| accepted(&c)).unwrap_or_else(failure),
        Err(message) => error(StatusCode::BAD_REQUEST, "invalid_input", &message),
    }
}

async fn command(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    match is_id(&id).then(|| app.service.command(&id)).flatten() {
        Some(found) => ok(found),
        None => failure(Failure::NotFound),
    }
}

