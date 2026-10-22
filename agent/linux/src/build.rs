//! Which build of this program runs: the lowercase hex SHA-256 of the program's own file. The version text stays the same from one build to the next, so this is what lets the
//! parent tell an old helper from a new one.
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::sync::OnceLock;

const OWN_FILE: &str = "/proc/self/exe";
const PIECE_BYTES: usize = 1 << 20;

/// The build of the file at `path`, read in pieces. None when it cannot be read as a file.
pub fn sha256_of_file(path: &Path) -> Option<String> {
    let mut file = File::open(path).ok()?;
    if !file.metadata().ok()?.is_file() {
        return None;
    }
    let mut hash = Sha256::new();
    let mut piece = vec![0u8; PIECE_BYTES];
    loop {
        let read = file.read(&mut piece).ok()?;
        if read == 0 {
            return Some(hex(&hash.finalize()));
        }
        hash.update(&piece[..read]);
    }
}

/// The build of the program that is running now. Worked out once, then kept.
pub fn running() -> Option<String> {
    static BUILD: OnceLock<Option<String>> = OnceLock::new();
    BUILD.get_or_init(|| sha256_of_file(Path::new(OWN_FILE))).clone()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!("ms-build-{name}-{}", std::process::id()));
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn the_build_is_the_lowercase_hex_sha256_of_the_file() {
        let dir = folder("abc");
        std::fs::write(dir.join("program"), b"abc").unwrap();
        assert_eq!(sha256_of_file(&dir.join("program")).as_deref(), Some("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    }

    #[test]
    fn a_big_file_is_read_in_pieces_and_gives_the_same_answer() {
        let dir = folder("big");
        let bytes = vec![7u8; PIECE_BYTES * 2 + 5];
        std::fs::write(dir.join("program"), &bytes).unwrap();
        assert_eq!(sha256_of_file(&dir.join("program")), Some(hex(&Sha256::digest(&bytes))));
    }

    #[test]
    fn a_missing_file_or_a_folder_has_no_build() {
        let dir = folder("none");
        assert_eq!(sha256_of_file(&dir.join("nothing")), None);
        assert_eq!(sha256_of_file(&dir), None);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn the_running_program_has_a_build_that_stays_the_same() {
        let first = running().expect("the test program can be read");
        assert_eq!(first.len(), 64);
        assert_eq!(running(), Some(first));
    }
}
