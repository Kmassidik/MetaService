//! The Agent half of contract/openapi.yaml, on axum.
use crate::models::{CONTRACT_VERSION, Refusal};
use crate::service::{Failure, Service};
use crate::validate::{is_id, BundleRequest, CreateRequest};
use axum::body::Body;
use axum::extract::{ConnectInfo, Path, Request, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{delete, get, post};
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
    bad: Mutex<HashMap<IpAddr, (u32, Instant)>>,
}

impl App {
    pub fn new(service: Arc<Service>, token: String, bad_token_limit: u32) -> Arc<App> {
        Arc::new(App { service, token, bad_token_limit, bad: Mutex::new(HashMap::new()) })
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
        .route("/v1/workloads", get(list).post(create))
        .route("/v1/workloads/:id/start", post(start))
        .route("/v1/workloads/:id/stop", post(stop))
        .route("/v1/workloads/:id", delete(remove))
        .route("/v1/bundle/install", post(install))
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

async fn command(State(app): State<Arc<App>>, Path(id): Path<String>) -> Response {
    match is_id(&id).then(|| app.service.command(&id)).flatten() {
        Some(found) => ok(found),
        None => failure(Failure::NotFound),
    }
}

