//! The hub's own SQLite database. It is the truth about links, pending
//! machines and peers; nothing here touches the parent database.
mod links;
mod peers;
mod pending;

pub use links::Link;
pub use peers::Peer;
pub use pending::{Pending, Share, STATE_APPROVED, STATE_PENDING, STATE_REFUSED};

use rusqlite::Connection;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};
use std::time::Duration;

const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS links (
  id TEXT PRIMARY KEY, os TEXT NOT NULL, cpu TEXT NOT NULL,
  created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, used_at INTEGER
);
CREATE TABLE IF NOT EXISTS pending (
  id TEXT PRIMARY KEY, link_id TEXT NOT NULL, secret_hash TEXT NOT NULL, code_hash TEXT NOT NULL,
  tries_left INTEGER NOT NULL, wg_public_key TEXT NOT NULL, os TEXT NOT NULL, cpu TEXT NOT NULL,
  hostname TEXT NOT NULL, ask_cores INTEGER NOT NULL, ask_ram_mb INTEGER NOT NULL, ask_disk_gb INTEGER NOT NULL,
  created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, state TEXT NOT NULL,
  name TEXT, address TEXT, share_cores INTEGER, share_ram_mb INTEGER, share_disk_gb INTEGER,
  enrollment_token TEXT
);
CREATE TABLE IF NOT EXISTS peers (
  name TEXT PRIMARY KEY COLLATE NOCASE, address TEXT NOT NULL UNIQUE, public_key TEXT NOT NULL UNIQUE,
  os TEXT NOT NULL, cpu TEXT NOT NULL, created_at INTEGER NOT NULL
);
";

pub struct Store {
    conn: Mutex<Connection>,
}

impl Store {
    pub fn open(path: &Path) -> rusqlite::Result<Store> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_memory() -> rusqlite::Result<Store> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> rusqlite::Result<Store> {
        conn.busy_timeout(BUSY_TIMEOUT)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Store { conn: Mutex::new(conn) })
    }

    fn db(&self) -> MutexGuard<'_, Connection> {
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }
}
