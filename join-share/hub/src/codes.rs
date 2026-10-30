//! Link ids, pending-machine secrets and the 6-digit approval code.
//! The code is only ever stored as a hash; the check is pure so the clock and
//! the try counter are easy to test.
use crate::crypto::{random_hex, secure_eq, sha256_hex};
use rand::Rng;

pub fn new_link_id() -> String {
    random_hex(24)
}

pub fn new_pending_id() -> String {
    random_hex(8)
}

pub fn new_secret() -> String {
    random_hex(24)
}

pub fn new_code() -> String {
    format!("{:06}", rand::thread_rng().gen_range(0..1_000_000))
}

/// Salted with the pending id so equal codes hash differently.
pub fn hash_code(pending_id: &str, code: &str) -> String {
    sha256_hex(format!("join-share-code:{pending_id}:{code}").as_bytes())
}

pub struct CodeState<'a> {
    pub pending_id: &'a str,
    pub code_hash: &'a str,
    pub tries_left: i64,
    pub expires_at: i64,
}

#[derive(Debug, PartialEq)]
pub enum CodeCheck {
    Accepted,
    /// Wrong; the caller stores the lowered count.
    Wrong { tries_left: i64 },
    Locked,
    Expired,
}

pub fn check_code(state: &CodeState, supplied: &str, now: i64) -> CodeCheck {
    if now >= state.expires_at {
        return CodeCheck::Expired;
    }
    if state.tries_left <= 0 {
        return CodeCheck::Locked;
    }
    if secure_eq(&hash_code(state.pending_id, supplied), state.code_hash) {
        return CodeCheck::Accepted;
    }
    CodeCheck::Wrong { tries_left: state.tries_left - 1 }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state<'a>(hash: &'a str, tries: i64) -> CodeState<'a> {
        CodeState { pending_id: "p1", code_hash: hash, tries_left: tries, expires_at: 1000 }
    }

    #[test]
    fn code_is_six_digits() {
        for _ in 0..50 {
            let code = new_code();
            assert_eq!(code.len(), 6);
            assert!(code.chars().all(|c| c.is_ascii_digit()));
        }
    }

    #[test]
    fn right_code_is_accepted_wrong_code_counts_down() {
        let hash = hash_code("p1", "123456");
        assert_eq!(check_code(&state(&hash, 5), "123456", 10), CodeCheck::Accepted);
        assert_eq!(check_code(&state(&hash, 5), "000000", 10), CodeCheck::Wrong { tries_left: 4 });
        assert_eq!(check_code(&state(&hash, 1), "000000", 10), CodeCheck::Wrong { tries_left: 0 });
    }

    #[test]
    fn five_wrong_tries_lock_it() {
        let hash = hash_code("p1", "123456");
        let mut tries = 5;
        for expected in (0..5).rev() {
            match check_code(&state(&hash, tries), "999999", 10) {
                CodeCheck::Wrong { tries_left } => assert_eq!(tries_left, expected),
                other => panic!("unexpected {other:?}"),
            }
            tries -= 1;
        }
        assert_eq!(check_code(&state(&hash, tries), "123456", 10), CodeCheck::Locked);
    }

    #[test]
    fn expiry_beats_a_right_code() {
        let hash = hash_code("p1", "123456");
        assert_eq!(check_code(&state(&hash, 5), "123456", 1000), CodeCheck::Expired);
        assert_eq!(check_code(&state(&hash, 5), "123456", 999), CodeCheck::Accepted);
    }

    #[test]
    fn hash_is_salted_by_pending_id() {
        assert_ne!(hash_code("a", "123456"), hash_code("b", "123456"));
    }

    #[test]
    fn ids_are_long_and_unique() {
        assert_eq!(new_link_id().len(), 48);
        assert_ne!(new_link_id(), new_link_id());
    }
}
