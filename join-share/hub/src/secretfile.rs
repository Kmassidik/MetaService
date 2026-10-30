//! Secret files (admin key, hub WireGuard key, hub config): created mode 600,
//! never logged.
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

const SECRET_MODE: u32 = 0o600;

/// Writes (replacing) a file that only the owner can read.
pub fn write_private(path: &Path, text: &str) -> Result<(), String> {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(SECRET_MODE)
        .open(path)
        .map_err(|e| format!("cannot write {}: {e}", path.display()))?;
    file.write_all(text.as_bytes()).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
    // `mode` only applies when the file is created; fix an older, looser file too.
    fs::set_permissions(path, std::os::unix::fs::PermissionsExt::from_mode(SECRET_MODE))
        .map_err(|e| format!("cannot protect {}: {e}", path.display()))
}

/// Reads the file's value, or makes one (first start) and stores it.
pub fn load_or_create(path: &Path, make: impl FnOnce() -> Result<String, String>) -> Result<String, String> {
    if path.exists() {
        let text = fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        return Ok(text.trim().to_string());
    }
    let value = make()?;
    write_private(path, &value)?;
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkit;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn created_once_with_mode_600_then_reused() {
        let dir = testkit::temp_dir();
        let path = dir.join("admin.key");
        let first = load_or_create(&path, || Ok("secret-1".into())).unwrap();
        let second = load_or_create(&path, || Ok("secret-2".into())).unwrap();
        assert_eq!((first.as_str(), second.as_str()), ("secret-1", "secret-1"));
        assert_eq!(fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        testkit::cleanup(&dir);
    }

    #[test]
    fn failing_maker_leaves_no_file() {
        let dir = testkit::temp_dir();
        let path = dir.join("k");
        assert!(load_or_create(&path, || Err("no".into())).is_err());
        assert!(!path.exists());
        testkit::cleanup(&dir);
    }
}
