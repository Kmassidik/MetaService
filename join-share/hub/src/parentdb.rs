//! The hub's only contact with the parent database: one enrollments INSERT per
//! approval (exactly like the parent's `EnrollmentStore.create`), plus a read of
//! machine names so a taken name is refused the same way the parent does.
use crate::constants::LIFETIME_SECS;
use crate::crypto::sha256_hex;
use rusqlite::{params, Connection, OpenFlags};
use std::net::Ipv4Addr;
use std::path::Path;
use std::time::Duration;

const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

/// Never creates the file: a wrong path must fail, not make an empty database.
fn open(path: &Path) -> Result<Connection, String> {
    let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_WRITE)
        .map_err(|e| format!("cannot open parent database: {e}"))?;
    conn.busy_timeout(BUSY_TIMEOUT).map_err(|e| format!("parent database: {e}"))?;
    Ok(conn)
}

pub fn insert_enrollment(path: &Path, token: &str, name: &str, address: Ipv4Addr, now: i64) -> Result<(), String> {
    let conn = open(path)?;
    conn.execute(
        "INSERT INTO enrollments (token_hash, machine_name, created_at, expires_at, expected_ip) VALUES (?1, ?2, ?3, ?4, ?5)",
        params![sha256_hex(token.as_bytes()), name, now, now + LIFETIME_SECS, address.to_string()],
    )
    .map_err(|e| format!("cannot insert enrollment: {e}"))?;
    Ok(())
}

/// Same rule as the parent: a machine with this id or (case-insensitive) name exists.
pub fn machine_name_taken(path: &Path, name: &str) -> Result<bool, String> {
    let conn = open(path)?;
    let mut stmt = conn.prepare("SELECT id, name FROM machines").map_err(|e| format!("parent machines: {e}"))?;
    let rows = stmt
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .map_err(|e| format!("parent machines: {e}"))?;
    let wanted = name.to_lowercase();
    for row in rows {
        let (id, existing) = row.map_err(|e| format!("parent machines: {e}"))?;
        if id == name || existing.to_lowercase() == wanted {
            return Ok(true);
        }
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkit;

    #[test]
    fn insert_matches_parent_create() {
        let (dir, db) = testkit::parent_db();
        insert_enrollment(&db, "tok123", "my-mac", "10.77.0.2".parse().unwrap(), 1000).unwrap();
        let conn = Connection::open(&db).unwrap();
        let row: (String, String, i64, i64, Option<i64>, String) = conn
            .query_row(
                "SELECT token_hash, machine_name, created_at, expires_at, used_at, expected_ip FROM enrollments",
                [],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)),
            )
            .unwrap();
        assert_eq!(row.0, sha256_hex(b"tok123"));
        assert_eq!((row.1.as_str(), row.2, row.3, row.4, row.5.as_str()), ("my-mac", 1000, 1900, None, "10.77.0.2"));
        testkit::cleanup(&dir);
    }

    #[test]
    fn duplicate_token_and_missing_file_fail() {
        let (dir, db) = testkit::parent_db();
        let ip: Ipv4Addr = "10.77.0.2".parse().unwrap();
        insert_enrollment(&db, "t", "a", ip, 1).unwrap();
        assert!(insert_enrollment(&db, "t", "b", ip, 1).is_err());
        assert!(insert_enrollment(&dir.join("missing.sqlite3"), "t", "b", ip, 1).is_err());
        assert!(!dir.join("missing.sqlite3").exists());
        testkit::cleanup(&dir);
    }

    #[test]
    fn machine_name_check_is_case_insensitive_and_covers_ids() {
        let (dir, db) = testkit::parent_db();
        Connection::open(&db).unwrap().execute("INSERT INTO machines (id, name) VALUES ('m-1', 'Office PC')", []).unwrap();
        assert!(machine_name_taken(&db, "office pc").unwrap());
        assert!(machine_name_taken(&db, "m-1").unwrap());
        assert!(!machine_name_taken(&db, "other").unwrap());
        testkit::cleanup(&dir);
    }
}
