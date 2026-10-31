//! The opaque cursor. Grammar (the parent never looks inside it):
//!
//! ```text
//! cursor   = "v1." source "." source          the first is the SSH log, the second the fail2ban log
//! source   = "a-" | "f-"  position            "a" auth, "f" fail2ban
//! position = "x"                              nothing known (no such file yet)
//!          | "j-" seconds                     the journal, last line read at this Unix second (the fallback when auth.log cannot be read)
//!          | dev "-" inode "-" offset         a file: its device, its inode, and the byte offset of the next unread line (all decimal)
//! ```
//! A different inode than the file now has means it was rotated; an offset past its size means it shrank.

const VERSION: &str = "v1";
const MAX_CURSOR_CHARS: usize = 200;
const UNKNOWN: &str = "x";
const JOURNAL: &str = "j";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FileMark {
    pub dev: u64,
    pub inode: u64,
    pub offset: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Position {
    Unknown,
    File(FileMark),
    Journal(i64),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cursor {
    pub auth: Position,
    pub fail2ban: Position,
}

impl Cursor {
    pub fn start() -> Cursor {
        Cursor {
            auth: Position::Unknown,
            fail2ban: Position::Unknown,
        }
    }

    pub fn encode(&self) -> String {
        format!(
            "{VERSION}.a-{}.f-{}",
            self.auth.encode(),
            self.fail2ban.encode()
        )
    }

    /// None for anything that is not exactly what `encode` writes.
    pub fn decode(text: &str) -> Option<Cursor> {
        if text.len() > MAX_CURSOR_CHARS {
            return None;
        }
        let mut parts = text.split('.');
        let (version, auth, fail2ban) = (parts.next()?, parts.next()?, parts.next()?);
        if version != VERSION || parts.next().is_some() {
            return None;
        }
        Some(Cursor {
            auth: Position::decode(auth.strip_prefix("a-")?)?,
            fail2ban: Position::decode(fail2ban.strip_prefix("f-")?)?,
        })
    }
}

impl Position {
    fn encode(&self) -> String {
        match self {
            Position::Unknown => UNKNOWN.into(),
            Position::File(mark) => format!("{}-{}-{}", mark.dev, mark.inode, mark.offset),
            Position::Journal(second) => format!("{JOURNAL}-{second}"),
        }
    }

    fn decode(text: &str) -> Option<Position> {
        if text == UNKNOWN {
            return Some(Position::Unknown);
        }
        let numbers: Vec<&str> = text.split('-').collect();
        match numbers.as_slice() {
            [JOURNAL, second] => Some(Position::Journal(plain_number(second)?.try_into().ok()?)),
            [dev, inode, offset] => Some(Position::File(FileMark {
                dev: plain_number(dev)?,
                inode: plain_number(inode)?,
                offset: plain_number(offset)?,
            })),
            _ => None,
        }
    }
}

/// Digits only: no sign, no plus, no spaces, so a garbled or negative value is refused.
fn plain_number(text: &str) -> Option<u64> {
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_cursor_survives_a_round_trip() {
        let mark = |offset| {
            Position::File(FileMark {
                dev: 2049,
                inode: 7_340_033,
                offset,
            })
        };
        for cursor in [
            Cursor::start(),
            Cursor {
                auth: mark(0),
                fail2ban: Position::Unknown,
            },
            Cursor {
                auth: Position::Journal(1_793_491_200),
                fail2ban: mark(u64::MAX),
            },
        ] {
            assert_eq!(Cursor::decode(&cursor.encode()), Some(cursor));
        }
        assert_eq!(
            Cursor {
                auth: mark(5),
                fail2ban: Position::Unknown
            }
            .encode(),
            "v1.a-2049-7340033-5.f-x"
        );
    }

    #[test]
    fn anything_garbled_is_refused() {
        let long = format!("v1.a-x.f-{}", "9".repeat(300));
        for bad in [
            "",
            "x",
            "v2.a-x.f-x",
            "v1.a-x",
            "v1.a-x.f-x.extra",
            "v1.a--1-2-3.f-x",
            "v1.a-1-2.f-x",
            "v1.a-1-2-3-4.f-x",
            "v1.a-+1-2-3.f-x",
            "v1.a-1-2-99999999999999999999999.f-x",
            "v1.f-x.a-x",
            "v1.a-j-.f-x",
            "v1.a-j--5.f-x",
            "v1.a-1-2-3.f-j-abc",
            "<script>",
            "../../etc/passwd",
            &long,
        ] {
            assert_eq!(Cursor::decode(bad), None, "{bad:?}");
        }
    }
}
