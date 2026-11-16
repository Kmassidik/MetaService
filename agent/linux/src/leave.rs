//! Taking this computer out of MetaService when the admin removes it in the panel and asks for it to be cleaned ("Clean the computer too").
//! The clean-up is `leave-from-panel.sh` (next to this file, the one copy; the Mac helper's `LeaveScript.swift` mirrors it and a test compares them), built into this helper, run from the join's own `joined.env`, so it also works for a computer
//! that joined with an older script. The sudo password comes in the request, goes to the script's standard input once, and is neither logged nor kept.
//! The script does the root step first and prints one marker line; only after `root-ok` does it delete anything, so a wrong password changes nothing.

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;

const SCRIPT: &str = include_str!("leave-from-panel.sh");
const MARKER: &str = "ms-leave: ";
/// The root step is one sudo call; this is only the bound for a stuck one.
const ROOT_STEP_SECONDS: u64 = 60;
/// The longest password accepted (the panel's own field limit is far below this).
pub const LONGEST_PASSWORD: usize = 256;

#[derive(Debug, PartialEq, Eq)]
pub enum Outcome {
    /// The root step worked; the rest of the clean-up runs on its own after this helper has answered.
    Leaving,
    /// This helper was not started by the join script, so there is nothing of a join to clean (a machine added over SSH).
    NotJoined,
    /// The root step did not work; nothing was changed. The text is safe to show.
    Failed(String),
}

/// The join folder is the parent of the helper's state folder (`~/.metaservice-join/state`).
pub fn join_home(state_dir: &Path) -> Option<PathBuf> {
    state_dir.parent().map(Path::to_path_buf)
}

fn read_marker(line: &str) -> Option<Outcome> {
    let said = line.strip_prefix(MARKER)?.trim();
    match said {
        "root-ok" => Some(Outcome::Leaving),
        "not-joined" | "unreadable" => Some(Outcome::NotJoined),
        other => Some(Outcome::Failed(other.strip_prefix("root-failed: ").unwrap_or(other).chars().take(200).collect())),
    }
}

/// Runs the clean-up. `sudo_bin` is only changed by tests.
pub async fn run(state_dir: &Path, password: &str, sudo_bin: Option<&str>) -> Outcome {
    let Some(home) = join_home(state_dir) else { return Outcome::NotJoined };
    if !home.join("joined.env").is_file() {
        return Outcome::NotJoined;
    }
    let mut command = Command::new("sh");
    command.arg("-c").arg(SCRIPT).arg("leave").arg(&home).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).kill_on_drop(false).process_group(0);
    if let Some(bin) = sudo_bin {
        command.env("MS_LEAVE_SUDO", bin);
    }
    let Ok(mut child) = command.spawn() else { return Outcome::Failed("the clean-up could not be started".into()) };
    if let Some(mut input) = child.stdin.take() {
        let _ = input.write_all(format!("{password}\n").as_bytes()).await;
    }
    let Some(output) = child.stdout.take() else { return Outcome::Failed("the clean-up could not be read".into()) };
    let mut lines = BufReader::new(output).lines();
    let wait = async {
        while let Ok(Some(line)) = lines.next_line().await {
            if let Some(found) = read_marker(&line) {
                return found;
            }
        }
        Outcome::Failed("the clean-up ended without an answer".into())
    };
    tokio::time::timeout(Duration::from_secs(ROOT_STEP_SECONDS), wait).await.unwrap_or_else(|_| Outcome::Failed("the clean-up took too long".into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn workdir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("ms-leave-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// A fake join home, and a stand-in sudo that accepts one password and logs what it was asked to run.
    fn world(dir: &Path) -> (PathBuf, String) {
        let home = dir.join(".metaservice-join");
        std::fs::create_dir_all(home.join("state")).unwrap();
        let unit = dir.join("unit.service");
        std::fs::write(&unit, "x").unwrap();
        let env = format!(
            "MS_NAME=fedora\nMS_OS=linux\nMS_BOOT=linux-systemd\nMS_UID=1000\nMS_IFACE=metaservice\nMS_CONF=/etc/wireguard/metaservice.conf\nMS_HOME={}\nMS_UNIT={}\nMS_LABEL=io.metaservice.join\nMS_WG_PLIST=\n",
            home.display(),
            unit.display()
        );
        std::fs::write(home.join("joined.env"), env).unwrap();
        let log = dir.join("calls.log");
        let sudo = dir.join("fake-sudo");
        std::fs::write(&sudo, format!("#!/bin/sh\nread -r pw\n[ \"$pw\" = secret ] || exit 1\necho \"sudo ran\" >> '{}'\nexit 0\n", log.display())).unwrap();
        std::fs::set_permissions(&sudo, std::fs::Permissions::from_mode(0o755)).unwrap();
        (home, sudo.display().to_string())
    }

    #[tokio::test]
    async fn a_wrong_password_changes_nothing() {
        let dir = workdir("wrong");
        let (home, sudo) = world(&dir);
        let outcome = run(&home.join("state"), "nope", Some(&sudo)).await;
        assert!(matches!(outcome, Outcome::Failed(ref why) if why.contains("sudo did not accept")), "{outcome:?}");
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(home.join("joined.env").is_file(), "the join must still be there");
        assert!(!dir.join("calls.log").exists());
    }

    #[tokio::test]
    async fn the_right_password_cleans_up_after_the_root_step() {
        let dir = workdir("right");
        let (home, sudo) = world(&dir);
        let outcome = run(&home.join("state"), "secret", Some(&sudo)).await;
        assert_eq!(outcome, Outcome::Leaving);
        assert!(std::fs::read_to_string(dir.join("calls.log")).unwrap().contains("sudo ran"));
        // The script waits two seconds so the helper can answer first, then deletes the join folder and the unit file.
        tokio::time::sleep(Duration::from_millis(3500)).await;
        assert!(!home.exists(), "the join folder is gone");
        assert!(!dir.join("unit.service").exists(), "the boot entry is gone");
    }

    #[tokio::test]
    async fn a_computer_that_never_joined_through_the_script_is_not_touched() {
        let dir = workdir("none");
        std::fs::create_dir_all(dir.join("agent").join("state")).unwrap();
        assert_eq!(run(&dir.join("agent").join("state"), "secret", None).await, Outcome::NotJoined);
    }

    #[test]
    fn markers_are_read_and_anything_else_is_ignored() {
        assert_eq!(read_marker("ms-leave: root-ok"), Some(Outcome::Leaving));
        assert_eq!(read_marker("ms-leave: not-joined"), Some(Outcome::NotJoined));
        assert_eq!(read_marker("ms-leave: root-failed: sudo needs a password"), Some(Outcome::Failed("sudo needs a password".into())));
        assert_eq!(read_marker("some other line"), None);
    }

    #[test]
    fn the_join_folder_is_the_parent_of_the_state_folder() {
        assert_eq!(join_home(Path::new("/home/k/.metaservice-join/state")), Some(PathBuf::from("/home/k/.metaservice-join")));
    }
}
