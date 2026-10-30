//! The far PC's side of the flow: register, poll status, and the lookups that
//! guard the helper download. Handlers in `http_public` stay thin.
use crate::codes::{hash_code, new_code, new_pending_id, new_secret};
use crate::constants::{CODE_TRIES, HELPER_PORT, KEEPALIVE_SECS, LIFETIME_SECS};
use crate::crypto::{is_wg_key, secure_eq, sha256_hex};
use crate::error::ApiError;
use crate::state::AppState;
use crate::store::{Link, Pending, Share, STATE_APPROVED, STATE_PENDING, STATE_REFUSED};
use crate::supported;
use axum::http::StatusCode;
use serde::Deserialize;
use serde_json::{json, Value};

const MAX_HOSTNAME_LEN: usize = 64;
const MAX_CORES: u32 = 4096;
const MAX_RAM_MB: u32 = 16 * 1024 * 1024;
const MAX_DISK_GB: u32 = 1_000_000;

#[derive(Deserialize)]
pub struct RegisterBody {
    pub wg_public_key: String,
    pub os: String,
    pub cpu: String,
    pub hostname: String,
    pub share: Share,
}

#[derive(Deserialize, Default)]
pub struct StatusQuery {
    pub pending: Option<String>,
    pub secret: Option<String>,
}

/// A link that exists, is unused and unexpired; every other case is the same 404.
pub fn live_link(state: &AppState, id: &str) -> Result<Link, ApiError> {
    match state.store.get_link(id)? {
        Some(link) if link.usable(state.now()) => Ok(link),
        _ => Err(ApiError::unknown_link()),
    }
}

fn plain_text_ok(text: &str) -> bool {
    !text.is_empty() && text.chars().count() <= MAX_HOSTNAME_LEN && !text.chars().any(char::is_control)
}

fn validate_register(state: &AppState, link: &Link, body: &RegisterBody) -> Result<(), ApiError> {
    if body.os != link.os || body.cpu != link.cpu {
        return Err(ApiError::bad("os_cpu_mismatch").with("reason", "This computer does not match the link."));
    }
    supported::check_pair(&state.config.builds, &body.os, &body.cpu)
        .map_err(|p| ApiError::bad(p.code).with("reason", p.reason))?;
    if !is_wg_key(&body.wg_public_key) {
        return Err(ApiError::bad("bad_public_key"));
    }
    if !plain_text_ok(&body.hostname) {
        return Err(ApiError::bad("bad_hostname"));
    }
    let share = &body.share;
    if share.cores > MAX_CORES || share.ram_mb > MAX_RAM_MB || share.disk_gb > MAX_DISK_GB {
        return Err(ApiError::bad("bad_share"));
    }
    if state.store.key_taken(&body.wg_public_key)? {
        return Err(ApiError::new(StatusCode::CONFLICT, "key_in_use"));
    }
    Ok(())
}

/// Uses the link up and stores a pending machine. The code is returned once, stored as a hash.
pub fn register(state: &AppState, link_id: &str, body: RegisterBody) -> Result<Value, ApiError> {
    let link = live_link(state, link_id)?;
    validate_register(state, &link, &body)?;
    let now = state.now();
    if !state.store.use_link(link_id, now)? {
        return Err(ApiError::unknown_link());
    }
    let (id, secret, code) = (new_pending_id(), new_secret(), new_code());
    state.store.insert_pending(&Pending {
        code_hash: hash_code(&id, &code),
        secret_hash: sha256_hex(secret.as_bytes()),
        id: id.clone(),
        link_id: link_id.to_string(),
        tries_left: CODE_TRIES,
        wg_public_key: body.wg_public_key,
        os: body.os,
        cpu: body.cpu,
        hostname: body.hostname,
        ask: body.share,
        created_at: now,
        expires_at: now + LIFETIME_SECS,
        state: STATE_PENDING.into(),
        name: None,
        address: None,
        share: None,
    })?;
    Ok(json!({ "pending": id, "secret": secret, "code": code, "expires_in": LIFETIME_SECS }))
}

/// The pending machine for this id + secret, or the same 404 as an unknown link.
pub fn find_pending(state: &AppState, id: &str, secret: &str) -> Result<Pending, ApiError> {
    let pending = state.store.get_pending(id)?.ok_or_else(ApiError::unknown_link)?;
    if !secure_eq(&sha256_hex(secret.as_bytes()), &pending.secret_hash) {
        return Err(ApiError::unknown_link());
    }
    Ok(pending)
}

pub fn status(state: &AppState, link_id: &str, query: &StatusQuery) -> Result<Value, ApiError> {
    let pending = find_pending(state, query.pending.as_deref().unwrap_or(""), query.secret.as_deref().unwrap_or(""))?;
    if pending.link_id != link_id {
        return Err(ApiError::unknown_link());
    }
    match pending.state.as_str() {
        STATE_REFUSED => Ok(json!({ "state": "refused" })),
        STATE_APPROVED => approved_body(state, &pending, query.secret.as_deref().unwrap_or("")),
        _ if state.now() >= pending.expires_at => Ok(json!({ "state": "expired" })),
        _ => Ok(json!({ "state": "pending" })),
    }
}

fn approved_body(state: &AppState, pending: &Pending, secret: &str) -> Result<Value, ApiError> {
    let config = &state.config;
    let helper = helper_file(state, pending)?;
    let bytes = std::fs::read(&helper).map_err(|e| ApiError::internal(format!("helper build unreadable: {e}")))?;
    let address = pending.address.clone().ok_or_else(|| ApiError::internal("approved without address"))?;
    let name = pending.name.clone().ok_or_else(|| ApiError::internal("approved without name"))?;
    let share = pending.share.ok_or_else(|| ApiError::internal("approved without share"))?;
    // Read the token last: a failure above must not use up the single read.
    let token = state.store.take_token(&pending.id)?;
    let mut machine = json!({
        "name": name,
        "parent_url": config.parent_url,
        "helper_bind": address,
        "helper_port": HELPER_PORT,
        "share": { "cores": share.cores, "ram_mb": share.ram_mb, "disk_gb": share.disk_gb },
    });
    if let Some(token) = token {
        machine["enrollment_token"] = json!(token);
    }
    Ok(json!({
        "state": "approved",
        "wireguard": {
            "address": format!("{address}/32"),
            "hub_public_key": state.hub_public_key,
            "endpoint": config.endpoint,
            "allowed_ips": format!("{}/32", config.net.hub()),
            "keepalive": KEEPALIVE_SECS,
        },
        "machine": machine,
        "download": {
            "url": format!("{}/dl/{}/{}?pending={}&secret={}", config.public_url, system_of(pending)?, crate::constants::HELPER_FILE, pending.id, secret),
            "sha256": sha256_hex(&bytes),
        },
    }))
}

fn system_of(pending: &Pending) -> Result<String, ApiError> {
    supported::system_of(&pending.os, &pending.cpu).ok_or_else(|| ApiError::internal("pending machine has no system"))
}

fn helper_file(state: &AppState, pending: &Pending) -> Result<std::path::PathBuf, ApiError> {
    let system = system_of(pending)?;
    let path = state.config.builds.file_for_system(&system);
    // Existence is checked at read time; a build removed since registering is a plain error.
    Ok(path)
}

/// The helper bytes, only for an approved machine of exactly this system.
pub fn helper_download(state: &AppState, target: &str, query: &StatusQuery) -> Result<Vec<u8>, ApiError> {
    let pending = find_pending(state, query.pending.as_deref().unwrap_or(""), query.secret.as_deref().unwrap_or(""))?;
    if pending.state != STATE_APPROVED || target != system_of(&pending)? {
        return Err(ApiError::unknown_link());
    }
    std::fs::read(helper_file(state, &pending)?).map_err(|e| ApiError::internal(format!("helper build unreadable: {e}")))
}
