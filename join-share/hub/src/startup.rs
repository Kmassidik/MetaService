//! First start and every start: state folder, keys, hub config, interface, firewall.
use crate::clock::Clock;
use crate::config::Config;
use crate::crypto::random_hex;
use crate::peers::hubconf::{self, HubPeer};
use crate::peers::WgControl;
use crate::ratelimit::RateLimiter;
use crate::secretfile;
use crate::state::{AppState, Shared};
use crate::store::Store;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::{Arc, Mutex};

const RATE_WINDOW_SECS: i64 = 60;
const STATE_DIR_MODE: u32 = 0o700;
const ADMIN_KEY_BYTES: usize = 32;

fn hub_key_path(dir: &Path) -> std::path::PathBuf {
    dir.join("hub.key")
}

/// Opens the state folder and database and loads (or makes) the keys. Starts nothing.
pub fn build_state(config: Config, wg: Arc<dyn WgControl>, clock: Clock) -> Result<Shared, String> {
    let dir = config.state_dir.clone();
    fs::create_dir_all(&dir).map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(STATE_DIR_MODE)).map_err(|e| format!("cannot protect state folder: {e}"))?;
    let store = Store::open(&dir.join("hub.sqlite3")).map_err(|e| format!("cannot open hub database: {e}"))?;
    let admin_key = secretfile::load_or_create(&dir.join("admin.key"), || Ok(random_hex(ADMIN_KEY_BYTES)))?;
    let hub_private = secretfile::load_or_create(&hub_key_path(&dir), || wg.generate_private_key())?;
    let hub_public_key = wg.public_key_of(&hub_private)?;
    Ok(Arc::new(AppState {
        limiter: RateLimiter::new(config.rate_limit_per_min, RATE_WINDOW_SECS),
        config,
        store,
        wg,
        clock,
        hub_public_key,
        admin_key,
        change_lock: Mutex::new(()),
    }))
}

/// Rebuilds `<wg name>.conf` from the database, restarts the interface and loads the firewall.
pub fn bring_up(state: &AppState) -> Result<(), String> {
    let dir = &state.config.state_dir;
    let private = fs::read_to_string(hub_key_path(dir)).map_err(|e| format!("cannot read hub key: {e}"))?;
    let peers = state.store.list_peers().map_err(|e| format!("cannot list peers: {e}"))?;
    let hub_peers: Vec<HubPeer> = peers
        .iter()
        .filter_map(|p| Some(HubPeer { name: p.name.clone(), public_key: p.public_key.clone(), address: p.address.parse().ok()? }))
        .collect();
    let text = hubconf::render(private.trim(), &state.config.net, state.config.wg_port, &hub_peers);
    let conf = dir.join(format!("{}.conf", state.config.wg_name));
    secretfile::write_private(&conf, &text)?;
    // A restart finds the interface already up; a failed down is fine then.
    if let Err(reason) = state.wg.down() {
        eprintln!("join-share: down before up: {reason}");
    }
    let iface = state.wg.up(&conf)?;
    eprintln!("join-share: {} up as {iface} with {} peer(s)", state.config.wg_name, hub_peers.len());
    state.wg.pf_load(&iface)
}

pub fn shut_down(state: &AppState) {
    if let Err(reason) = state.wg.pf_unload() {
        eprintln!("join-share: pf-unload: {reason}");
    }
    if let Err(reason) = state.wg.down() {
        eprintln!("join-share: down: {reason}");
    }
}
