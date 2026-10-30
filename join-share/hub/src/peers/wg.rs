//! The only way the hub touches WireGuard and pf. Tests use `FakeWg`.
use std::net::Ipv4Addr;
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub struct PeerStat {
    pub public_key: String,
    /// Unix seconds of the last handshake, 0 when there never was one.
    pub last_handshake: i64,
}

pub trait WgControl: Send + Sync {
    fn generate_private_key(&self) -> Result<String, String>;
    fn public_key_of(&self, private_key: &str) -> Result<String, String>;
    /// Brings the hub interface up from the config file; returns the interface name.
    fn up(&self, conf: &Path) -> Result<String, String>;
    fn down(&self) -> Result<(), String>;
    fn add_peer(&self, public_key: &str, address: Ipv4Addr) -> Result<(), String>;
    fn remove_peer(&self, public_key: &str) -> Result<(), String>;
    fn pf_load(&self, iface: &str) -> Result<(), String>;
    fn pf_unload(&self) -> Result<(), String>;
    fn show(&self) -> Result<Vec<PeerStat>, String>;
}
