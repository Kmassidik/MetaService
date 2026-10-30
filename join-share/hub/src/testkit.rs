//! Helpers shared by unit and integration tests (temp folders, a parent
//! database with the real `enrollments` DDL). Not used by the programs.
use rusqlite::Connection;
use std::path::{Path, PathBuf};

/// `enrollments` exactly as the parent's migrations 1 and 3 build it, plus the
/// two `machines` columns the hub reads.
pub const PARENT_DDL: &str = "
CREATE TABLE enrollments (
  id INTEGER PRIMARY KEY AUTOINCREMENT, token_hash TEXT NOT NULL UNIQUE, machine_name TEXT NOT NULL,
  created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, used_at INTEGER
);
ALTER TABLE enrollments ADD COLUMN expected_ip TEXT;
CREATE TABLE machines (id TEXT PRIMARY KEY, name TEXT NOT NULL);
";

pub fn temp_dir() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("join-share-test-{}", crate::crypto::random_hex(8)));
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

pub fn cleanup(dir: &Path) {
    let _ = std::fs::remove_dir_all(dir);
}

/// A temp folder holding a parent database; returns (folder, database path).
pub fn parent_db() -> (PathBuf, PathBuf) {
    let dir = temp_dir();
    let db = dir.join("root.sqlite3");
    Connection::open(&db).expect("open").execute_batch(PARENT_DDL).expect("ddl");
    (dir, db)
}
