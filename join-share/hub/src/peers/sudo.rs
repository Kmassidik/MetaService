//! The real `WgControl`: root actions go through `sudo -n join-share-root ...`;
//! key generation uses the unprivileged `wg` tool.
use super::wg::{PeerStat, WgControl};
use serde::Deserialize;
use std::io::Write;
use std::net::Ipv4Addr;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Homebrew is not on PATH in a launchd job.
const WG_CANDIDATES: [&str; 3] = ["/opt/homebrew/bin/wg", "/usr/local/bin/wg", "/usr/bin/wg"];

pub struct SudoWg {
    helper: PathBuf,
    wg: PathBuf,
    wg_name: String,
    anchor: String,
    parent_port: u16,
}

impl SudoWg {
    pub fn new(helper: PathBuf, wg_name: String, anchor: String, parent_port: u16) -> Self {
        let wg = WG_CANDIDATES.iter().map(PathBuf::from).find(|p| p.exists()).unwrap_or_else(|| PathBuf::from("wg"));
        Self { helper, wg, wg_name, anchor, parent_port }
    }

    fn root(&self, args: &[&str]) -> Result<String, String> {
        let out = Command::new("sudo")
            .arg("-n")
            .arg(&self.helper)
            .args(args)
            .args(["--wg", &self.wg_name, "--anchor", &self.anchor, "--parent-port", &self.parent_port.to_string()])
            .output()
            .map_err(|e| format!("cannot run sudo: {e}"))?;
        if !out.status.success() {
            return Err(format!("root helper failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }
}

#[derive(Deserialize)]
struct ShownPeer {
    public_key: String,
    last_handshake: i64,
}

impl WgControl for SudoWg {
    fn generate_private_key(&self) -> Result<String, String> {
        let out = Command::new(&self.wg).arg("genkey").output().map_err(|e| format!("wg genkey: {e}"))?;
        if !out.status.success() {
            return Err("wg genkey failed".into());
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }

    fn public_key_of(&self, private_key: &str) -> Result<String, String> {
        let mut child = Command::new(&self.wg)
            .arg("pubkey")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("wg pubkey: {e}"))?;
        let mut stdin = child.stdin.take().ok_or("wg pubkey: no stdin")?;
        stdin.write_all(private_key.as_bytes()).map_err(|e| format!("wg pubkey: {e}"))?;
        drop(stdin);
        let out = child.wait_with_output().map_err(|e| format!("wg pubkey: {e}"))?;
        if !out.status.success() {
            return Err("wg pubkey failed".into());
        }
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }

    fn up(&self, conf: &Path) -> Result<String, String> {
        self.root(&["up", &conf.to_string_lossy()])
    }

    fn down(&self) -> Result<(), String> {
        self.root(&["down"]).map(|_| ())
    }

    fn add_peer(&self, public_key: &str, address: Ipv4Addr) -> Result<(), String> {
        self.root(&["add-peer", public_key, &address.to_string()]).map(|_| ())
    }

    fn remove_peer(&self, public_key: &str) -> Result<(), String> {
        self.root(&["remove-peer", public_key]).map(|_| ())
    }

    fn pf_load(&self, iface: &str) -> Result<(), String> {
        // The helper reads the network from its own validated copy of the config.
        self.root(&["pf-load", iface]).map(|_| ())
    }

    fn pf_unload(&self) -> Result<(), String> {
        self.root(&["pf-unload"]).map(|_| ())
    }

    fn show(&self) -> Result<Vec<PeerStat>, String> {
        let text = self.root(&["show"])?;
        let peers: Vec<ShownPeer> = serde_json::from_str(&text).map_err(|e| format!("bad show output: {e}"))?;
        Ok(peers.into_iter().map(|p| PeerStat { public_key: p.public_key, last_handshake: p.last_handshake }).collect())
    }
}
