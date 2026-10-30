use super::Store;
use rusqlite::{params, OptionalExtension};

#[derive(Debug, Clone)]
pub struct Link {
    pub id: String,
    pub os: String,
    pub cpu: String,
    pub created_at: i64,
    pub expires_at: i64,
    pub used_at: Option<i64>,
}

impl Link {
    pub fn usable(&self, now: i64) -> bool {
        self.used_at.is_none() && now < self.expires_at
    }
}

impl Store {
    pub fn insert_link(&self, link: &Link) -> rusqlite::Result<()> {
        self.db().execute(
            "INSERT INTO links (id, os, cpu, created_at, expires_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![link.id, link.os, link.cpu, link.created_at, link.expires_at],
        )?;
        Ok(())
    }

    pub fn get_link(&self, id: &str) -> rusqlite::Result<Option<Link>> {
        self.db()
            .query_row(
                "SELECT id, os, cpu, created_at, expires_at, used_at FROM links WHERE id = ?1",
                [id],
                |r| {
                    Ok(Link {
                        id: r.get(0)?,
                        os: r.get(1)?,
                        cpu: r.get(2)?,
                        created_at: r.get(3)?,
                        expires_at: r.get(4)?,
                        used_at: r.get(5)?,
                    })
                },
            )
            .optional()
    }

    /// True only for the one caller that uses an unused, unexpired link up.
    pub fn use_link(&self, id: &str, now: i64) -> rusqlite::Result<bool> {
        let changed = self.db().execute(
            "UPDATE links SET used_at = ?2 WHERE id = ?1 AND used_at IS NULL AND expires_at > ?2",
            params![id, now],
        )?;
        Ok(changed == 1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn link(expires_at: i64) -> Link {
        Link { id: "l1".into(), os: "mac".into(), cpu: "arm64".into(), created_at: 0, expires_at, used_at: None }
    }

    #[test]
    fn link_is_used_exactly_once() {
        let store = Store::open_memory().unwrap();
        store.insert_link(&link(900)).unwrap();
        assert!(store.use_link("l1", 10).unwrap());
        assert!(!store.use_link("l1", 11).unwrap());
        assert!(!store.get_link("l1").unwrap().unwrap().usable(11));
    }

    #[test]
    fn expired_link_cannot_be_used() {
        let store = Store::open_memory().unwrap();
        store.insert_link(&link(900)).unwrap();
        assert!(!store.use_link("l1", 900).unwrap());
        assert!(store.get_link("nope").unwrap().is_none());
    }
}
