//! "Update helper" for a computer that joined through Share a PC: the panel has no SSH login on it, so the helper replaces itself. It downloads the build the parent
//! offers (over the same tunnel and with the same machine token it already reports with), checks the build's SHA-256 against the one the panel asked for, writes it next
//! to itself, and a small script outside this program's process group swaps the file and restarts the boot entry (and puts the old file back if the new helper does not come up).
//! Nothing here uses sudo: the helper only changes its own file and its own user service.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use sha2::{Digest, Sha256};

/// The largest helper accepted (the real ones are about 7 MB).
const MAX_BYTES: u64 = 64 * 1024 * 1024;
const DOWNLOAD_SECONDS: u64 = 120;
const ELF_MAGIC: &[u8] = b"\x7fELF";
/// How long the new helper gets to say it is up before the old file is put back.
const SETTLE_SECONDS: u64 = 25;
const SWAP_SCRIPT: &str = include_str!("swap-helper.sh");

#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// The new build was downloaded and checked; the swap and restart are under way.
    Started,
    /// This helper already is that build.
    Current,
    /// Not started by the join script, so it has no boot entry to restart (a machine added over SSH is updated over SSH).
    NotJoined,
    /// Nothing was changed. The text is safe to show.
    Failed(String),
}

/// A build as the panel names it: lowercase hex, long enough to tell builds apart.
pub fn valid_build(text: &str) -> bool {
    (8..=64).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Downloads the helper from the parent. Blocking: run it off the async threads.
fn download(root: &str, token: &str) -> Result<Vec<u8>, String> {
    let reply = ureq::get(&format!("{root}/v1/agents/build")).timeout(Duration::from_secs(DOWNLOAD_SECONDS)).set("Authorization", &format!("Bearer {token}")).call()
        .map_err(|_| "the parent did not give the new helper".to_string())?;
    let mut bytes = Vec::new();
    reply.into_reader().take(MAX_BYTES + 1).read_to_end(&mut bytes).map_err(|_| "the new helper could not be read".to_string())?;
    if bytes.len() as u64 > MAX_BYTES {
        return Err("the new helper is too large".into());
    }
    Ok(bytes)
}

/// Checks the bytes are the build the panel asked for and a Linux program.
fn verified(bytes: &[u8], wanted: &str) -> Result<(), String> {
    if !bytes.starts_with(ELF_MAGIC) {
        return Err("the downloaded file is not a Linux program".into());
    }
    if !hex(&Sha256::digest(bytes)).starts_with(wanted) {
        return Err("the downloaded helper is not the build the panel asked for, so it was not installed".into());
    }
    Ok(())
}

/// Reads one `KEY=value` line. The join script writes values shell-quoted (`shq`), because `leave.sh`
/// sources this file, so surrounding single quotes are part of the file but not of the value.
fn env_value(env_text: &str, key: &str) -> Option<String> {
    let raw = env_text.lines().find_map(|line| line.strip_prefix(key).and_then(|rest| rest.strip_prefix('='))).unwrap_or("").trim().to_string();
    let unquoted = match (raw.chars().next(), raw.chars().rev().next()) {
        (Some('\''), Some('\'')) if raw.len() >= 2 => raw[1..raw.len() - 1].to_string(),
        _ => raw,
    };
    Some(unquoted)
}

/// Runs the update. `source` is `(root, token)`, or None for a helper with no parent to download from. `own` is this program's file, `current` its build.
pub async fn run(join_home: &Path, source: Option<(String, String)>, wanted: &str, own: &Path, current: Option<&str>, systemd_run: bool) -> Outcome {
    let env = join_home.join("joined.env");
    let Ok(env_text) = std::fs::read_to_string(&env) else { return Outcome::NotJoined };
    let label = env_value(&env_text, "MS_LABEL").unwrap_or_default();
    if label.is_empty() || !label.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b'_')) {
        return Outcome::NotJoined;
    }
    if current.is_some_and(|build| build.starts_with(wanted)) {
        return Outcome::Current;
    }
    let Some((root, token)) = source else { return Outcome::Failed("this helper has no parent to download from".into()) };
    let bytes = match tokio::task::spawn_blocking(move || download(&root, &token)).await {
        Ok(Ok(bytes)) => bytes,
        Ok(Err(why)) => return Outcome::Failed(why),
        Err(_) => return Outcome::Failed("the download did not finish".into()),
    };
    if let Err(why) = verified(&bytes, wanted) {
        return Outcome::Failed(why);
    }
    let fresh = PathBuf::from(format!("{}.new", own.display()));
    if write_executable(&fresh, &bytes).is_err() {
        return Outcome::Failed("the new helper could not be written next to the old one".into());
    }
    match start_swap(&fresh, own, &label, systemd_run) {
        Ok(()) => Outcome::Started,
        Err(why) => {
            let _ = std::fs::remove_file(&fresh);
            Outcome::Failed(why)
        }
    }
}

fn write_executable(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, bytes)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755))
}

/// The swap runs in its own transient user unit (`systemd-run --user`), so restarting this helper's own unit does not take the swap down with it; without systemd-run
/// it runs in its own process group, which is enough where there is no unit to restart.
fn start_swap(fresh: &Path, own: &Path, label: &str, systemd_run: bool) -> Result<(), String> {
    let mut command = if systemd_run {
        let mut command = std::process::Command::new("systemd-run");
        command.args(["--user", "--collect", "--quiet", "sh", "-c", SWAP_SCRIPT, "swap"]);
        command
    } else {
        let mut command = std::process::Command::new("sh");
        command.args(["-c", SWAP_SCRIPT, "swap"]);
        std::os::unix::process::CommandExt::process_group(&mut command, 0);
        command
    };
    command.arg(fresh).arg(own).arg(label).arg(SETTLE_SECONDS.to_string()).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    command.spawn().map(drop).map_err(|_| "the swap could not be started".to_string())
}

/// True when `systemd-run --user` is there to use.
pub fn has_systemd_run() -> bool {
    std::process::Command::new("systemd-run").arg("--version").stdout(Stdio::null()).stderr(Stdio::null()).status().map(|status| status.success()).unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_build_is_lowercase_hex_of_a_sensible_length() {
        assert!(valid_build("3bf6cd0c"));
        assert!(valid_build(&"a".repeat(64)));
        assert!(!valid_build("3BF6CD0C"));
        assert!(!valid_build("abc"));
        assert!(!valid_build("zzzzzzzz"));
        assert!(!valid_build(&"a".repeat(65)));
    }

    #[test]
    fn only_the_asked_for_linux_program_is_accepted() {
        let mut program = b"\x7fELF".to_vec();
        program.extend_from_slice(b"the rest of the program");
        let build = hex(&Sha256::digest(&program));
        assert!(verified(&program, &build[..8]).is_ok());
        assert!(verified(&program, "deadbeef").unwrap_err().contains("not the build"));
        assert!(verified(b"MZ not linux", "deadbeef").unwrap_err().contains("not a Linux program"));
    }

    fn world(name: &str, env: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ms-selfup-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        if !env.is_empty() {
            std::fs::write(dir.join("joined.env"), env).unwrap();
        }
        dir
    }

    #[tokio::test]
    async fn a_computer_that_did_not_join_through_the_script_is_left_alone() {
        let dir = world("none", "");
        assert_eq!(run(&dir, None, "deadbeef", &dir.join("agent"), None, false).await, Outcome::NotJoined);
    }

    #[tokio::test]
    async fn a_helper_that_already_is_that_build_does_nothing() {
        let dir = world("current", "MS_LABEL=io.metaservice.join\n");
        assert_eq!(run(&dir, None, "deadbeef", &dir.join("agent"), Some("deadbeefcafe"), false).await, Outcome::Current);
    }

    #[tokio::test]
    async fn the_quoted_env_file_the_join_script_writes_is_accepted() {
        // Regression 2026-11-16: join.sh writes every value shell-quoted for leave.sh to source,
        // so MS_LABEL arrives as 'io.metaservice.join' with literal quotes. The reader refused it,
        // every self-update answered not_joined and the panel said "Login needed". This is the
        // laptop's real joined.env line.
        let dir = world("quoted", "MS_OS='linux'\nMS_LABEL='io.metaservice.join'\nMS_UID='1000'\n");
        assert_eq!(run(&dir, None, "deadbeef", &dir.join("agent"), Some("deadbeefcafe"), false).await, Outcome::Current);
    }

    #[tokio::test]
    async fn a_quoted_label_with_odd_characters_inside_is_still_refused() {
        let dir = world("quotedbad", "MS_LABEL='bad label;rm -rf'\n");
        assert_eq!(run(&dir, None, "deadbeef", &dir.join("agent"), None, false).await, Outcome::NotJoined);
    }

    #[tokio::test]
    async fn a_label_with_odd_characters_is_refused_before_anything_runs() {
        let dir = world("label", "MS_LABEL=bad label;rm -rf\n");
        assert_eq!(run(&dir, None, "deadbeef", &dir.join("agent"), None, false).await, Outcome::NotJoined);
    }

    #[tokio::test]
    async fn without_a_parent_to_download_from_nothing_changes() {
        let dir = world("noparent", "MS_LABEL=io.metaservice.join\n");
        assert!(matches!(run(&dir, None, "deadbeef", &dir.join("agent"), None, false).await, Outcome::Failed(why) if why.contains("no parent")));
    }
}
