//! Admin approval: check the code, give an address, add the WireGuard peer and
//! insert the parent enrollment. Each step that fails undoes the one before it.
use crate::codes::{check_code, CodeCheck, CodeState};
use crate::crypto::random_hex;
use crate::error::ApiError;
use crate::parentdb;
use crate::state::AppState;
use crate::store::{Peer, Pending, Share, STATE_PENDING};
use axum::http::StatusCode;
use serde::Deserialize;
use std::net::Ipv4Addr;

const MAX_NAME_LEN: usize = 40;
const TOKEN_BYTES: usize = 32;

#[derive(Deserialize)]
pub struct ApproveRequest {
    pub code: String,
    pub name: String,
    pub share: Share,
}

/// Letters, digits, dot, dash, underscore: safe in a config comment and a file name.
pub fn valid_machine_name(name: &str) -> bool {
    let chars_ok = name.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-' || b == b'_');
    !name.is_empty() && name.len() <= MAX_NAME_LEN && chars_ok
}

fn open_pending(state: &AppState, id: &str) -> Result<Pending, ApiError> {
    let pending = state.store.get_pending(id)?.ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "unknown_pending"))?;
    if pending.state != STATE_PENDING {
        return Err(ApiError::new(StatusCode::CONFLICT, "not_pending"));
    }
    Ok(pending)
}

fn verify_code(state: &AppState, pending: &Pending, supplied: &str) -> Result<(), ApiError> {
    let code_state = CodeState {
        pending_id: &pending.id,
        code_hash: &pending.code_hash,
        tries_left: pending.tries_left,
        expires_at: pending.expires_at,
    };
    match check_code(&code_state, supplied, state.now()) {
        CodeCheck::Accepted => Ok(()),
        CodeCheck::Expired => Err(ApiError::new(StatusCode::GONE, "expired")),
        CodeCheck::Locked => Err(ApiError::new(StatusCode::FORBIDDEN, "locked")),
        CodeCheck::Wrong { .. } => {
            let tries_left = state.store.record_wrong_code(&pending.id)?;
            Err(ApiError::new(StatusCode::FORBIDDEN, "wrong_code").with("tries_left", tries_left))
        }
    }
}

fn check_choices(state: &AppState, pending: &Pending, request: &ApproveRequest) -> Result<(), ApiError> {
    if !valid_machine_name(&request.name) {
        return Err(ApiError::bad("bad_name"));
    }
    if !request.share.fits_within(&pending.ask) {
        return Err(ApiError::bad("share_too_high"));
    }
    let taken_here = state.store.name_taken(&request.name)?;
    let taken_in_parent = parentdb::machine_name_taken(&state.config.parent_db, &request.name).map_err(ApiError::internal)?;
    if taken_here || taken_in_parent {
        return Err(ApiError::new(StatusCode::CONFLICT, "name_taken"));
    }
    Ok(())
}

fn free_address(state: &AppState) -> Result<Ipv4Addr, ApiError> {
    let used = state.store.used_addresses()?;
    state.config.net.lowest_free(&used).ok_or_else(|| ApiError::new(StatusCode::CONFLICT, "network_full"))
}

/// Returns the far PC's new address.
pub fn approve(state: &AppState, id: &str, request: ApproveRequest) -> Result<Ipv4Addr, ApiError> {
    let _one_at_a_time = state.change_lock.lock().unwrap_or_else(|e| e.into_inner());
    let pending = open_pending(state, id)?;
    verify_code(state, &pending, &request.code)?;
    check_choices(state, &pending, &request)?;
    let address = free_address(state)?;
    state.wg.add_peer(&pending.wg_public_key, address).map_err(|e| {
        eprintln!("join-share: add-peer failed: {e}");
        ApiError::new(StatusCode::BAD_GATEWAY, "wireguard_failed")
    })?;
    let token = random_hex(TOKEN_BYTES);
    let now = state.now();
    let saved = parentdb::insert_enrollment(&state.config.parent_db, &token, &request.name, address, now).map_err(ApiError::internal);
    let peer = Peer {
        name: request.name,
        address: address.to_string(),
        public_key: pending.wg_public_key.clone(),
        os: pending.os.clone(),
        cpu: pending.cpu.clone(),
        created_at: now,
    };
    let finished = saved.and_then(|_| state.store.finish_approval(id, &peer, &request.share, &token).map_err(ApiError::from));
    if let Err(error) = finished {
        undo_peer(state, &pending.wg_public_key);
        return Err(error);
    }
    Ok(address)
}

fn undo_peer(state: &AppState, public_key: &str) {
    if let Err(reason) = state.wg.remove_peer(public_key) {
        eprintln!("join-share: could not undo add-peer: {reason}");
    }
}

/// Removes the WireGuard peer and frees the address.
pub fn remove_peer(state: &AppState, name: &str) -> Result<(), ApiError> {
    let _one_at_a_time = state.change_lock.lock().unwrap_or_else(|e| e.into_inner());
    let peer = state.store.get_peer(name)?.ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "unknown_peer"))?;
    state.wg.remove_peer(&peer.public_key).map_err(|e| {
        eprintln!("join-share: remove-peer failed: {e}");
        ApiError::new(StatusCode::BAD_GATEWAY, "wireguard_failed")
    })?;
    state.store.remove_peer(&peer.name)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn machine_names() {
        assert!(valid_machine_name("my-mac_1.local"));
        assert!(!valid_machine_name(""));
        assert!(!valid_machine_name("has space"));
        assert!(!valid_machine_name("new\nline"));
        assert!(!valid_machine_name(&"a".repeat(41)));
    }
}
