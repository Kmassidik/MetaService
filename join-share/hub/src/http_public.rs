//! Public listener (CONTRACT section 4): join script, register, status, helper download.
use crate::constants::BODY_LIMIT_BYTES;
use crate::error::ApiError;
use crate::join_flow::{self, RegisterBody, StatusQuery};
use crate::script;
use crate::state::Shared;
use crate::supported;
use axum::extract::rejection::JsonRejection;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Path, Query, Request, State};
use axum::http::{header, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::Value;
use std::net::SocketAddr;

const MAX_FORWARDED_IP_LEN: usize = 64;

pub fn router(state: Shared) -> Router {
    Router::new()
        .route("/j/:link", get(script_handler))
        .route("/j/:link/register", post(register_handler))
        .route("/j/:link/status", get(status_handler))
        .route("/dl/:target/metaservice-agent", get(download_handler))
        .layer(DefaultBodyLimit::max(BODY_LIMIT_BYTES))
        .layer(middleware::from_fn_with_state(state.clone(), rate_limit))
        .with_state(state)
}

/// Behind the Cloudflare tunnel every connection is local; the real client is in this header.
pub fn client_ip(req: &Request) -> String {
    let forwarded = req
        .headers()
        .get("cf-connecting-ip")
        .and_then(|v| v.to_str().ok())
        .filter(|v| v.len() <= MAX_FORWARDED_IP_LEN);
    if let Some(ip) = forwarded {
        return ip.to_string();
    }
    match req.extensions().get::<ConnectInfo<SocketAddr>>() {
        Some(ConnectInfo(addr)) => addr.ip().to_string(),
        None => "local".to_string(),
    }
}

async fn rate_limit(State(state): State<Shared>, req: Request, next: Next) -> Response {
    if !state.limiter.allow(&client_ip(&req), state.now()) {
        return ApiError::new(StatusCode::TOO_MANY_REQUESTS, "rate_limited").into_response();
    }
    next.run(req).await
}

#[derive(Deserialize)]
struct ScriptQuery {
    os: Option<String>,
    cpu: Option<String>,
}

async fn script_handler(
    State(state): State<Shared>,
    Path(link_id): Path<String>,
    Query(query): Query<ScriptQuery>,
) -> Result<Response, ApiError> {
    let link = join_flow::live_link(&state, &link_id)?;
    let os = query.os.unwrap_or_else(|| link.os.clone());
    let cpu = query.cpu.unwrap_or_else(|| link.cpu.clone());
    if os != link.os || cpu != link.cpu {
        return Err(ApiError::bad("os_cpu_mismatch").with("reason", "This computer does not match the link."));
    }
    supported::check_pair(&state.config.builds, &os, &cpu).map_err(|p| ApiError::bad(p.code).with("reason", p.reason))?;
    let text = script::join_script(&link.id, &state.config.public_url, &os, &cpu);
    Ok(([(header::CONTENT_TYPE, "text/x-shellscript")], text).into_response())
}

async fn register_handler(
    State(state): State<Shared>,
    Path(link_id): Path<String>,
    body: Result<Json<RegisterBody>, JsonRejection>,
) -> Result<Json<Value>, ApiError> {
    let Json(body) = body.map_err(|r| ApiError::new(r.status(), "bad_request"))?;
    join_flow::register(&state, &link_id, body).map(Json)
}

async fn status_handler(
    State(state): State<Shared>,
    Path(link_id): Path<String>,
    Query(query): Query<StatusQuery>,
) -> Result<Json<Value>, ApiError> {
    join_flow::status(&state, &link_id, &query).map(Json)
}

async fn download_handler(
    State(state): State<Shared>,
    Path(target): Path<String>,
    Query(query): Query<StatusQuery>,
) -> Result<Response, ApiError> {
    let bytes = join_flow::helper_download(&state, &target, &query)?;
    Ok(([(header::CONTENT_TYPE, "application/octet-stream")], bytes).into_response())
}
