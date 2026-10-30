//! In-memory `WgControl` for tests: no WireGuard, no sudo, no pf.
use super::wg::{PeerStat, WgControl};
use crate::crypto::{base64_encode, sha256_hex};
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};

#[derive(Default)]
struct Inner {
    peers: Vec<(String, Ipv4Addr)>,
    calls: Vec<String>,
    fail_add: bool,
    handshakes: HashMap<String, i64>,
}

#[derive(Default)]
pub struct FakeWg {
    inner: Mutex<Inner>,
}

impl FakeWg {
    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.inner.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn peers(&self) -> Vec<(String, Ipv4Addr)> {
        self.lock().peers.clone()
    }

    pub fn calls(&self) -> Vec<String> {
        self.lock().calls.clone()
    }

    pub fn set_fail_add(&self, fail: bool) {
        self.lock().fail_add = fail;
    }

    pub fn set_handshake(&self, public_key: &str, at: i64) {
        self.lock().handshakes.insert(public_key.to_string(), at);
    }

    fn record(&self, call: &str) {
        self.lock().calls.push(call.to_string());
    }
}

impl WgControl for FakeWg {
    fn generate_private_key(&self) -> Result<String, String> {
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        Ok(base64_encode(&bytes))
    }

    fn public_key_of(&self, private_key: &str) -> Result<String, String> {
        Ok(base64_encode(&Sha256::digest(private_key.as_bytes())))
    }

    fn up(&self, _conf: &Path) -> Result<String, String> {
        self.record("up");
        Ok("fake0".into())
    }

    fn down(&self) -> Result<(), String> {
        self.record("down");
        Ok(())
    }

    fn add_peer(&self, public_key: &str, address: Ipv4Addr) -> Result<(), String> {
        let mut inner = self.lock();
        if inner.fail_add {
            return Err("fake add-peer failure".into());
        }
        inner.calls.push(format!("add-peer {}", sha256_hex(public_key.as_bytes())));
        inner.peers.push((public_key.to_string(), address));
        Ok(())
    }

    fn remove_peer(&self, public_key: &str) -> Result<(), String> {
        let mut inner = self.lock();
        inner.calls.push("remove-peer".into());
        inner.peers.retain(|(k, _)| k != public_key);
        Ok(())
    }

    fn pf_load(&self, _iface: &str) -> Result<(), String> {
        self.record("pf-load");
        Ok(())
    }

    fn pf_unload(&self) -> Result<(), String> {
        self.record("pf-unload");
        Ok(())
    }

    fn show(&self) -> Result<Vec<PeerStat>, String> {
        let inner = self.lock();
        Ok(inner
            .peers
            .iter()
            .map(|(k, _)| PeerStat { public_key: k.clone(), last_handshake: *inner.handshakes.get(k).unwrap_or(&0) })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fake_keys_are_valid_and_peers_roundtrip() {
        let wg = FakeWg::default();
        let private = wg.generate_private_key().unwrap();
        let public = wg.public_key_of(&private).unwrap();
        assert!(crate::crypto::is_wg_key(&private) && crate::crypto::is_wg_key(&public));
        wg.add_peer(&public, "10.77.0.2".parse().unwrap()).unwrap();
        assert_eq!(wg.show().unwrap().len(), 1);
        wg.remove_peer(&public).unwrap();
        assert!(wg.peers().is_empty());
    }
}
