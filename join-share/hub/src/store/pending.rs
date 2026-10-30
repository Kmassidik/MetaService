use super::peers::Peer;
use super::Store;
use rusqlite::{params, OptionalExtension, Row};
use serde::{Deserialize, Serialize};

pub const STATE_PENDING: &str = "pending";
pub const STATE_APPROVED: &str = "approved";
pub const STATE_REFUSED: &str = "refused";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Share {
    pub cores: u32,
    pub ram_mb: u32,
    pub disk_gb: u32,
}

impl Share {
    /// Approval may lower the asked share, never raise it.
    pub fn fits_within(&self, asked: &Share) -> bool {
        self.cores <= asked.cores && self.ram_mb <= asked.ram_mb && self.disk_gb <= asked.disk_gb
    }
}

#[derive(Debug, Clone)]
pub struct Pending {
    pub id: String,
    pub link_id: String,
    pub secret_hash: String,
    pub code_hash: String,
    pub tries_left: i64,
    pub wg_public_key: String,
    pub os: String,
    pub cpu: String,
    pub hostname: String,
    pub ask: Share,
    pub created_at: i64,
    pub expires_at: i64,
    pub state: String,
    pub name: Option<String>,
    pub address: Option<String>,
    /// The share fixed at approval (possibly lowered); None before.
    pub share: Option<Share>,
}

const COLS: &str = "id, link_id, secret_hash, code_hash, tries_left, wg_public_key, os, cpu, hostname, \
                    ask_cores, ask_ram_mb, ask_disk_gb, created_at, expires_at, state, name, address, \
                    share_cores, share_ram_mb, share_disk_gb";

fn approved_share(cores: Option<u32>, ram_mb: Option<u32>, disk_gb: Option<u32>) -> Option<Share> {
    Some(Share { cores: cores?, ram_mb: ram_mb?, disk_gb: disk_gb? })
}

fn from_row(r: &Row) -> rusqlite::Result<Pending> {
    Ok(Pending {
        id: r.get(0)?,
        link_id: r.get(1)?,
        secret_hash: r.get(2)?,
        code_hash: r.get(3)?,
        tries_left: r.get(4)?,
        wg_public_key: r.get(5)?,
        os: r.get(6)?,
        cpu: r.get(7)?,
        hostname: r.get(8)?,
        ask: Share { cores: r.get(9)?, ram_mb: r.get(10)?, disk_gb: r.get(11)? },
        created_at: r.get(12)?,
        expires_at: r.get(13)?,
        state: r.get(14)?,
        name: r.get(15)?,
        address: r.get(16)?,
        share: approved_share(r.get(17)?, r.get(18)?, r.get(19)?),
    })
}

impl Store {
    pub fn insert_pending(&self, p: &Pending) -> rusqlite::Result<()> {
        self.db().execute(
            "INSERT INTO pending (id, link_id, secret_hash, code_hash, tries_left, wg_public_key, os, cpu, hostname, \
             ask_cores, ask_ram_mb, ask_disk_gb, created_at, expires_at, state) \
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15)",
            params![
                p.id, p.link_id, p.secret_hash, p.code_hash, p.tries_left, p.wg_public_key, p.os, p.cpu, p.hostname,
                p.ask.cores, p.ask.ram_mb, p.ask.disk_gb, p.created_at, p.expires_at, p.state
            ],
        )?;
        Ok(())
    }

    pub fn get_pending(&self, id: &str) -> rusqlite::Result<Option<Pending>> {
        self.db()
            .query_row(&format!("SELECT {COLS} FROM pending WHERE id = ?1"), [id], from_row)
            .optional()
    }

    /// Machines still waiting for an admin, newest last.
    pub fn list_open_pending(&self, now: i64) -> rusqlite::Result<Vec<Pending>> {
        let conn = self.db();
        let mut stmt = conn.prepare(&format!(
            "SELECT {COLS} FROM pending WHERE state = ?1 AND expires_at > ?2 ORDER BY created_at, id"
        ))?;
        let rows = stmt.query_map(params![STATE_PENDING, now], from_row)?;
        rows.collect()
    }

    /// Counts one wrong code; at zero tries the machine is refused. Returns tries left.
    pub fn record_wrong_code(&self, id: &str) -> rusqlite::Result<i64> {
        let mut conn = self.db();
        let tx = conn.transaction()?;
        tx.execute("UPDATE pending SET tries_left = tries_left - 1 WHERE id = ?1", [id])?;
        let left: i64 = tx.query_row("SELECT tries_left FROM pending WHERE id = ?1", [id], |r| r.get(0))?;
        if left <= 0 {
            tx.execute("UPDATE pending SET state = ?2 WHERE id = ?1", params![id, STATE_REFUSED])?;
        }
        tx.commit()?;
        Ok(left.max(0))
    }

    pub fn refuse_pending(&self, id: &str) -> rusqlite::Result<bool> {
        let changed = self.db().execute(
            "UPDATE pending SET state = ?2 WHERE id = ?1 AND state = ?3",
            params![id, STATE_REFUSED, STATE_PENDING],
        )?;
        Ok(changed == 1)
    }

    /// Adds the peer and marks the machine approved in one transaction.
    pub fn finish_approval(&self, id: &str, peer: &Peer, share: &Share, token: &str) -> rusqlite::Result<()> {
        let mut conn = self.db();
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO peers (name, address, public_key, os, cpu, created_at) VALUES (?1,?2,?3,?4,?5,?6)",
            params![peer.name, peer.address, peer.public_key, peer.os, peer.cpu, peer.created_at],
        )?;
        tx.execute(
            "UPDATE pending SET state = ?2, name = ?3, address = ?4, share_cores = ?5, share_ram_mb = ?6, \
             share_disk_gb = ?7, enrollment_token = ?8 WHERE id = ?1",
            params![id, STATE_APPROVED, peer.name, peer.address, share.cores, share.ram_mb, share.disk_gb, token],
        )?;
        tx.commit()
    }

    /// The enrollment token is handed out once: read and clear in one step.
    pub fn take_token(&self, id: &str) -> rusqlite::Result<Option<String>> {
        let mut conn = self.db();
        let tx = conn.transaction()?;
        let token: Option<String> = tx.query_row("SELECT enrollment_token FROM pending WHERE id = ?1", [id], |r| r.get(0))?;
        tx.execute("UPDATE pending SET enrollment_token = NULL WHERE id = ?1", [id])?;
        tx.commit()?;
        Ok(token)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pending(id: &str) -> Pending {
        Pending {
            id: id.into(), link_id: "l1".into(), secret_hash: "s".into(), code_hash: "c".into(), tries_left: 5,
            wg_public_key: "k".into(), os: "mac".into(), cpu: "arm64".into(), hostname: "h".into(),
            ask: Share { cores: 4, ram_mb: 8192, disk_gb: 50 }, created_at: 10, expires_at: 910,
            state: STATE_PENDING.into(), name: None, address: None, share: None,
        }
    }

    #[test]
    fn five_wrong_codes_refuse_it() {
        let store = Store::open_memory().unwrap();
        store.insert_pending(&pending("p1")).unwrap();
        for expected in [4, 3, 2, 1, 0] {
            assert_eq!(store.record_wrong_code("p1").unwrap(), expected);
        }
        assert_eq!(store.get_pending("p1").unwrap().unwrap().state, STATE_REFUSED);
    }

    #[test]
    fn open_list_hides_refused_and_expired() {
        let store = Store::open_memory().unwrap();
        store.insert_pending(&pending("p1")).unwrap();
        store.insert_pending(&pending("p2")).unwrap();
        assert!(store.refuse_pending("p2").unwrap());
        assert!(!store.refuse_pending("p2").unwrap());
        assert_eq!(store.list_open_pending(100).unwrap().len(), 1);
        assert!(store.list_open_pending(910).unwrap().is_empty());
    }

    #[test]
    fn token_is_given_once() {
        let store = Store::open_memory().unwrap();
        store.insert_pending(&pending("p1")).unwrap();
        let peer = Peer { name: "m".into(), address: "10.77.0.2".into(), public_key: "k".into(), os: "mac".into(), cpu: "arm64".into(), created_at: 20 };
        store.finish_approval("p1", &peer, &Share { cores: 2, ram_mb: 1024, disk_gb: 10 }, "tok").unwrap();
        assert_eq!(store.take_token("p1").unwrap().as_deref(), Some("tok"));
        assert_eq!(store.take_token("p1").unwrap(), None);
        let stored = store.get_pending("p1").unwrap().unwrap();
        assert_eq!(stored.address.as_deref(), Some("10.77.0.2"));
        assert_eq!(stored.share, Some(Share { cores: 2, ram_mb: 1024, disk_gb: 10 }));
    }

    #[test]
    fn share_may_only_be_lowered() {
        let ask = Share { cores: 4, ram_mb: 8192, disk_gb: 50 };
        assert!(Share { cores: 2, ram_mb: 8192, disk_gb: 10 }.fits_within(&ask));
        assert!(!Share { cores: 5, ram_mb: 8192, disk_gb: 10 }.fits_within(&ask));
    }
}
