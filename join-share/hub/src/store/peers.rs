use super::Store;
use rusqlite::{params, Row};
use std::net::Ipv4Addr;

#[derive(Debug, Clone)]
pub struct Peer {
    pub name: String,
    pub address: String,
    pub public_key: String,
    pub os: String,
    pub cpu: String,
    pub created_at: i64,
}

const COLS: &str = "name, address, public_key, os, cpu, created_at";

fn from_row(r: &Row) -> rusqlite::Result<Peer> {
    Ok(Peer {
        name: r.get(0)?,
        address: r.get(1)?,
        public_key: r.get(2)?,
        os: r.get(3)?,
        cpu: r.get(4)?,
        created_at: r.get(5)?,
    })
}

impl Store {
    pub fn list_peers(&self) -> rusqlite::Result<Vec<Peer>> {
        let conn = self.db();
        let mut stmt = conn.prepare(&format!("SELECT {COLS} FROM peers ORDER BY created_at, name"))?;
        let rows = stmt.query_map([], from_row)?;
        rows.collect()
    }

    pub fn get_peer(&self, name: &str) -> rusqlite::Result<Option<Peer>> {
        let found = self.list_peers()?;
        Ok(found.into_iter().find(|p| p.name.eq_ignore_ascii_case(name)))
    }

    pub fn remove_peer(&self, name: &str) -> rusqlite::Result<bool> {
        let changed = self.db().execute("DELETE FROM peers WHERE name = ?1", params![name])?;
        Ok(changed == 1)
    }

    pub fn name_taken(&self, name: &str) -> rusqlite::Result<bool> {
        Ok(self.get_peer(name)?.is_some())
    }

    pub fn key_taken(&self, public_key: &str) -> rusqlite::Result<bool> {
        let count: i64 = self.db().query_row("SELECT COUNT(*) FROM peers WHERE public_key = ?1", [public_key], |r| r.get(0))?;
        Ok(count > 0)
    }

    pub fn used_addresses(&self) -> rusqlite::Result<Vec<Ipv4Addr>> {
        let peers = self.list_peers()?;
        Ok(peers.iter().filter_map(|p| p.address.parse().ok()).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(crate) fn peer(name: &str, address: &str, key: &str) -> Peer {
        Peer { name: name.into(), address: address.into(), public_key: key.into(), os: "mac".into(), cpu: "arm64".into(), created_at: 1 }
    }

    fn put(store: &Store, p: &Peer) {
        store
            .db()
            .execute(
                "INSERT INTO peers (name, address, public_key, os, cpu, created_at) VALUES (?1,?2,?3,?4,?5,?6)",
                params![p.name, p.address, p.public_key, p.os, p.cpu, p.created_at],
            )
            .unwrap();
    }

    #[test]
    fn peers_list_remove_and_free_the_address() {
        let store = Store::open_memory().unwrap();
        put(&store, &peer("a", "10.77.0.2", "k1"));
        put(&store, &peer("b", "10.77.0.3", "k2"));
        assert_eq!(store.used_addresses().unwrap().len(), 2);
        assert!(store.remove_peer("a").unwrap());
        assert!(!store.remove_peer("a").unwrap());
        assert_eq!(store.used_addresses().unwrap(), vec!["10.77.0.3".parse::<Ipv4Addr>().unwrap()]);
    }

    #[test]
    fn name_and_key_checks_ignore_case_for_names() {
        let store = Store::open_memory().unwrap();
        put(&store, &peer("My-Mac", "10.77.0.2", "k1"));
        assert!(store.name_taken("my-mac").unwrap());
        assert!(!store.name_taken("other").unwrap());
        assert!(store.key_taken("k1").unwrap());
        assert!(!store.key_taken("k9").unwrap());
    }
}
