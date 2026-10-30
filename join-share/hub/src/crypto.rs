//! Small hashing / encoding helpers. WireGuard keys are base64 of 32 bytes; a
//! 20-line encoder here avoids a crate for it.
use rand::RngCore;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
/// Last base64 char of a 32-byte key carries only 4 bits, so it is one of these.
const KEY_LAST_CHARS: &[u8] = b"AEIMQUYcgkosw048";

pub fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn sha256_hex(data: &[u8]) -> String {
    to_hex(&Sha256::digest(data))
}

pub fn random_hex(byte_count: usize) -> String {
    let mut bytes = vec![0u8; byte_count];
    rand::thread_rng().fill_bytes(&mut bytes);
    to_hex(&bytes)
}

/// Constant-time string compare (both sides hashed first so length does not leak).
pub fn secure_eq(a: &str, b: &str) -> bool {
    let ha = Sha256::digest(a.as_bytes());
    let hb = Sha256::digest(b.as_bytes());
    ha.as_slice().ct_eq(hb.as_slice()).into()
}

pub fn base64_encode(data: &[u8]) -> String {
    let mut out = String::new();
    for chunk in data.chunks(3) {
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = ((chunk[0] as u32) << 16) | (b1 << 8) | b2;
        out.push(B64[(n >> 18 & 63) as usize] as char);
        out.push(B64[(n >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 { B64[(n >> 6 & 63) as usize] as char } else { '=' });
        out.push(if chunk.len() > 2 { B64[(n & 63) as usize] as char } else { '=' });
    }
    out
}

/// A WireGuard key: 44 base64 chars ending in one `=`, decoding to 32 bytes.
pub fn is_wg_key(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 44 || b[43] != b'=' {
        return false;
    }
    b[..43].iter().all(|c| B64.contains(c)) && KEY_LAST_CHARS.contains(&b[42])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_known_value() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn encoded_32_bytes_is_a_wg_key() {
        let key = base64_encode(&[7u8; 32]);
        assert_eq!(key.len(), 44);
        assert!(is_wg_key(&key));
    }

    #[test]
    fn wg_key_rejects_bad_shapes() {
        assert!(!is_wg_key("short"));
        assert!(!is_wg_key(&format!("{}=", "A".repeat(42) + "B")));
        assert!(!is_wg_key(&format!("{}!=", "A".repeat(42))));
        assert!(!is_wg_key(&"A".repeat(44)));
    }

    #[test]
    fn secure_eq_matches_only_equal() {
        assert!(secure_eq("abc", "abc"));
        assert!(!secure_eq("abc", "abd"));
        assert!(!secure_eq("abc", ""));
    }

    #[test]
    fn random_hex_has_length_and_varies() {
        assert_eq!(random_hex(16).len(), 32);
        assert_ne!(random_hex(16), random_hex(16));
    }
}
