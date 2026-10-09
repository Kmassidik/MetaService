//! Small file helpers: private files (mode 600), and refusing secrets that other users can read.
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::Path;

/// Writes a file that only its owner can read, replacing any existing one.
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(path)?;
    file.set_permissions(std::fs::Permissions::from_mode(0o600))?;
    file.write_all(bytes)
}

/// The text of a secret file. It must exist, hold something, and be readable by its owner only.
pub fn read_secret(path: &Path) -> Result<String, String> {
    let text = std::fs::read_to_string(path).ok().map(|t| t.trim().to_string()).filter(|t| !t.is_empty())
        .ok_or_else(|| format!("no token in {}; run `metaservice-agent enroll` first", path.display()))?;
    let mode = std::fs::metadata(path).map(|m| m.permissions().mode()).unwrap_or(0o777);
    if mode & 0o077 != 0 {
        return Err(format!("{} must be mode 600 (owner only)", path.display()));
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_files_are_mode_600_and_loose_ones_are_refused() {
        let path = std::env::temp_dir().join(format!("ms-secret-{}", rand::random::<u64>()));
        write_private(&path, b" token-value \n").unwrap();
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(read_secret(&path).unwrap(), "token-value");
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(read_secret(&path).unwrap_err().contains("mode 600"));
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        write_private(&path, b"  \n").unwrap();
        assert!(read_secret(&path).unwrap_err().contains("no token"));
        let _ = std::fs::remove_file(path);
    }
}
