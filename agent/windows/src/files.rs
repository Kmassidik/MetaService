//! Small file helpers for tokens and secrets.
use std::io::Write;
// Windows: the join folder lives under the user profile, whose ACLs already keep other users out,
// so the unix permission bits the Linux and Mac helpers set have no equivalent here.
use std::path::Path;

/// Writes a file that only its owner can read, replacing any existing one.
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).open(path)?;
    file.write_all(bytes)
}

/// The text of a secret file. It must exist, hold something, and be readable by its owner only.
pub fn read_secret(path: &Path) -> Result<String, String> {
    let text = std::fs::read_to_string(path).ok().map(|t| t.trim().to_string()).filter(|t| !t.is_empty())
        .ok_or_else(|| format!("no token in {}; run `metaservice-agent enroll` first", path.display()))?;
    if !path.is_file() {
        return Err(format!("{} is missing", path.display()));
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_private_writes_and_read_secret_trims() {
        let path = std::env::temp_dir().join(format!("ms-secret-{}", std::process::id()));
        write_private(&path, b" token-value \n").unwrap();
        assert_eq!(read_secret(&path).unwrap(), "token-value");
        std::fs::remove_file(&path).unwrap();
        assert!(read_secret(&path).is_err());
    }
}
