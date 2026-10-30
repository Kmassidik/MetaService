//! Which (os, cpu) pairs can join. A pair maps to the parent's "system" name;
//! the helper file for it is the parent's own build (CONTRACT section 2):
//! `darwin-arm64` is the file at JOIN_SHARE_MAC_AGENT, the others are
//! `<builds dir>/metaservice-agent-<system>`.
use serde_json::{json, Value};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

pub const OSES: [&str; 3] = ["mac", "linux", "windows"];
pub const CPUS: [&str; 2] = ["arm64", "x86_64"];
/// Pairs proven end to end so far; a build for any other pair is "untested".
const PROVEN: [(&str, &str); 2] = [("mac", "arm64"), ("linux", "x86_64")];
const EXECUTABLE_BITS: u32 = 0o111;

#[derive(Debug, Clone)]
pub struct Builds {
    pub dir: PathBuf,
    pub mac_agent: Option<PathBuf>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    Ready,
    Untested,
    Missing,
    Soon,
}

impl State {
    pub fn as_str(self) -> &'static str {
        match self {
            State::Ready => "ready",
            State::Untested => "untested",
            State::Missing => "missing",
            State::Soon => "soon",
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct PairProblem {
    pub code: &'static str,
    pub reason: &'static str,
}

/// The parent's system name, e.g. `linux-x86_64`; None for windows or unknown words.
pub fn system_of(os: &str, cpu: &str) -> Option<String> {
    if !CPUS.contains(&cpu) {
        return None;
    }
    match os {
        "mac" => Some(format!("darwin-{cpu}")),
        "linux" => Some(format!("linux-{cpu}")),
        _ => None,
    }
}

impl Builds {
    /// Where the helper file for a system lives (it may not exist).
    pub fn file_for_system(&self, system: &str) -> PathBuf {
        match (system, &self.mac_agent) {
            ("darwin-arm64", Some(path)) => path.clone(),
            ("darwin-arm64", None) => self.dir.join("metaservice-agent-darwin-arm64"),
            _ => self.dir.join(format!("metaservice-agent-{system}")),
        }
    }

    /// The helper file for a pair, only when it exists and is executable.
    pub fn helper_for(&self, os: &str, cpu: &str) -> Option<PathBuf> {
        let path = self.file_for_system(&system_of(os, cpu)?);
        is_executable_file(&path).then_some(path)
    }
}

fn is_executable_file(path: &Path) -> bool {
    std::fs::metadata(path).is_ok_and(|m| m.is_file() && m.permissions().mode() & EXECUTABLE_BITS != 0)
}

pub fn state_of(builds: &Builds, os: &str, cpu: &str) -> State {
    if os == "windows" {
        return State::Soon;
    }
    if builds.helper_for(os, cpu).is_none() {
        return State::Missing;
    }
    if PROVEN.contains(&(os, cpu)) { State::Ready } else { State::Untested }
}

/// Ok when a link or registration for this pair makes sense.
pub fn check_pair(builds: &Builds, os: &str, cpu: &str) -> Result<(), PairProblem> {
    if !OSES.contains(&os) || !CPUS.contains(&cpu) {
        return Err(PairProblem { code: "bad_os_cpu", reason: "Unknown operating system or CPU." });
    }
    match state_of(builds, os, cpu) {
        State::Ready | State::Untested => Ok(()),
        State::Soon => Err(PairProblem { code: "windows_soon", reason: "Windows is coming soon." }),
        State::Missing => Err(PairProblem { code: "no_build", reason: "There is no helper build for this computer yet." }),
    }
}

/// The table behind the three buttons on the admin page.
pub fn table(builds: &Builds) -> Value {
    let rows: Vec<Value> = OSES
        .iter()
        .map(|os| {
            let cpus: Vec<Value> = CPUS
                .iter()
                .map(|cpu| json!({ "cpu": cpu, "state": state_of(builds, os, cpu).as_str() }))
                .collect();
            json!({ "os": os, "cpus": cpus })
        })
        .collect();
    Value::Array(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testkit;

    /// Writes executable fake builds: linux ones into the folder, the Mac one elsewhere.
    pub(crate) fn builds_with(files: &[&str]) -> (PathBuf, Builds) {
        let dir = testkit::temp_dir();
        let mut builds = Builds { dir: dir.clone(), mac_agent: None };
        for system in files {
            let path = if *system == "darwin-arm64" {
                let mac = dir.join("mac-helper");
                builds.mac_agent = Some(mac.clone());
                mac
            } else {
                dir.join(format!("metaservice-agent-{system}"))
            };
            std::fs::write(&path, b"bin").unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        }
        (dir, builds)
    }

    #[test]
    fn systems_map_from_pairs() {
        assert_eq!(system_of("mac", "arm64").as_deref(), Some("darwin-arm64"));
        assert_eq!(system_of("mac", "x86_64").as_deref(), Some("darwin-x86_64"));
        assert_eq!(system_of("linux", "arm64").as_deref(), Some("linux-arm64"));
        assert_eq!(system_of("windows", "arm64"), None);
        assert_eq!(system_of("linux", "../x"), None);
    }

    #[test]
    fn states_follow_files_and_proven_pairs() {
        let (dir, builds) = builds_with(&["darwin-arm64", "linux-arm64", "linux-x86_64"]);
        assert_eq!(state_of(&builds, "mac", "arm64"), State::Ready);
        assert_eq!(state_of(&builds, "linux", "x86_64"), State::Ready);
        assert_eq!(state_of(&builds, "linux", "arm64"), State::Untested);
        assert_eq!(state_of(&builds, "mac", "x86_64"), State::Missing);
        assert_eq!(state_of(&builds, "windows", "x86_64"), State::Soon);
        testkit::cleanup(&dir);
    }

    #[test]
    fn a_file_that_is_not_executable_counts_as_missing() {
        let (dir, builds) = builds_with(&["linux-x86_64"]);
        let path = builds.file_for_system("linux-x86_64");
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert_eq!(state_of(&builds, "linux", "x86_64"), State::Missing);
        testkit::cleanup(&dir);
    }

    #[test]
    fn check_pair_codes() {
        let (dir, builds) = builds_with(&["linux-x86_64"]);
        assert!(check_pair(&builds, "linux", "x86_64").is_ok());
        assert_eq!(check_pair(&builds, "windows", "arm64").unwrap_err().code, "windows_soon");
        assert_eq!(check_pair(&builds, "mac", "arm64").unwrap_err().code, "no_build");
        assert_eq!(check_pair(&builds, "beos", "arm64").unwrap_err().code, "bad_os_cpu");
        assert_eq!(check_pair(&builds, "../x", "arm64").unwrap_err().code, "bad_os_cpu");
        testkit::cleanup(&dir);
    }

    #[test]
    fn table_shape() {
        let (dir, builds) = builds_with(&["darwin-arm64"]);
        let t = table(&builds);
        assert_eq!(t[0]["os"], "mac");
        assert_eq!(t[0]["cpus"][0], json!({"cpu": "arm64", "state": "ready"}));
        assert_eq!(t[0]["cpus"][1]["state"], "missing");
        assert_eq!(t[2]["cpus"][1]["state"], "soon");
        testkit::cleanup(&dir);
    }
}
