//! The jailer's argument list for one sandbox: the whole of it, built here from a validated id and two numbers, with every flag and every path a
//! constant of this build.
//!
//! The jailer puts Firecracker in a chroot under its own unprivileged user, joins the sandbox's network namespace, and makes its own cgroups
//! (sandbox/README.md, Safety). Nothing on this list comes from a request except the id, the uid and the gid, and those are checked first: an id is the
//! contract's 20 lowercase letters and digits, so it can never be `--help` or climb out of a directory.
use super::{FIRECRACKER, Step};
use crate::sandbox::record::is_sandbox_id;
use std::path::Path;

/// The jailer's own cgroup mode: Firecracker asks for cgroups v2, and restored snapshots are slow on v1.
const CGROUP_VERSION: &str = "2";
/// One open file limit for the whole process, so a runaway sandbox cannot hold the machine's file table.
const RESOURCE_LIMIT: &str = "no-file=1024";
/// uid 0 is root, and a jailer that drops to it is no jail at all.
const FIRST_UNPRIVILEGED_ID: u32 = 1;
const LAST_ID: u32 = 65_535;
/// A namespace name is a file under `/run/netns`: plain characters only, and shorter than any path can be.
const NAMESPACE_MAX: usize = 64;
/// Where the config lands inside the chroot: the jailer chroots before Firecracker reads it, so the path is absolute within that root.
pub const CONFIG_IN_CHROOT: &str = "/config.json";

/// The argv for `jailer`, without the program itself. `chroot` is the jailer's `--chroot-dir`; `netns` is the sandbox's namespace; `config` is where
/// this build wrote the Firecracker config, as Firecracker will see it after the chroot.
pub fn jailer_arguments(id: &str, uid: u32, gid: u32, chroot: &Path, netns: &str, config: &Path) -> Result<Vec<String>, String> {
    if !is_sandbox_id(id) {
        return Err("a sandbox id is 20 lowercase letters or digits".into());
    }
    if !(FIRST_UNPRIVILEGED_ID..=LAST_ID).contains(&uid) || !(FIRST_UNPRIVILEGED_ID..=LAST_ID).contains(&gid) {
        return Err("a sandbox's uid and gid are unprivileged: 1 to 65535".into());
    }
    if !chroot.is_absolute() || !config.is_absolute() {
        return Err("the jailer's chroot and the Firecracker config are absolute paths".into());
    }
    if !is_namespace(netns) {
        return Err(format!("{netns:?} is not a network namespace name"));
    }
    let chroot = path_text(chroot)?;
    let config = path_text(config)?;
    Ok(vec![
        "--id".into(), id.into(),
        "--exec-file".into(), FIRECRACKER.into(),
        "--uid".into(), uid.to_string(),
        "--gid".into(), gid.to_string(),
        "--chroot-dir".into(), chroot,
        "--netns".into(), netns.into(),
        "--cgroup-version".into(), CGROUP_VERSION.into(),
        "--resource-limit".into(), RESOURCE_LIMIT.into(),
        // Not `--daemonize`: the jailer execs Firecracker in the process it forks, so the runner keeps that pid and can stop it later.
        // Everything after this belongs to Firecracker: the config file and no API socket, so there is no second way in beside the one config.
        "--".into(), "--no-api".into(),
        "--config-file".into(), config,
    ])
}

/// The whole start: the jailer, with the list above.
pub fn start_step(id: &str, uid: u32, gid: u32, chroot: &Path, netns: &str, config: &Path) -> Result<Step, String> {
    Ok(Step::new(super::JAILER, jailer_arguments(id, uid, gid, chroot, netns, config)?))
}

/// A path as an argument: it must be text (the machine's paths are) and must not hold a NUL, which no program can be given.
fn path_text(path: &Path) -> Result<String, String> {
    let text = path.to_str().ok_or_else(|| format!("{} is not a path this machine can use", path.display()))?;
    if text.contains('\0') {
        return Err("a path cannot hold a NUL byte".into());
    }
    Ok(text.to_string())
}

/// A namespace name as `/run/netns` takes it: letters, digits, `-` and `_`, and nothing that could name another directory.
fn is_namespace(name: &str) -> bool {
    !name.is_empty() && name.len() <= NAMESPACE_MAX && name.chars().all(|character| character.is_ascii_alphanumeric() || matches!(character, '-' | '_'))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "abcdefghij0123456789";

    fn arguments() -> Vec<String> {
        jailer_arguments(ID, 30_007, 30_007, Path::new("/run/metaservice-sandbox/ms7"), "ms7", Path::new(CONFIG_IN_CHROOT)).ok().unwrap()
    }

    #[test]
    fn the_jailer_gets_one_fixed_argument_list() {
        assert_eq!(arguments(), [
            "--id", ID,
            "--exec-file", "/usr/local/bin/firecracker",
            "--uid", "30007",
            "--gid", "30007",
            "--chroot-dir", "/run/metaservice-sandbox/ms7",
            "--netns", "ms7",
            "--cgroup-version", "2",
            "--resource-limit", "no-file=1024",
            "--",
            "--no-api",
            "--config-file", "/config.json",
        ].map(String::from));
        let step = start_step(ID, 30_007, 30_007, Path::new("/jail/ms7"), "ms7", Path::new(CONFIG_IN_CHROOT)).ok().unwrap();
        assert_eq!(step.program, "/usr/local/bin/jailer");
        assert_eq!(step.arguments.len(), 20, "the jailer's own flags, the `--`, and Firecracker's two");
    }

    #[test]
    fn a_hostile_id_is_refused_before_it_reaches_any_argument() {
        for bad in ["a b", "../x", "--help", "", "ABCDEFGHIJ0123456789", "abcdefghij0123456789 --uid 0", "abcdefghij012345678\n"] {
            assert!(jailer_arguments(bad, 30_007, 30_007, Path::new("/j"), "ms7", Path::new(CONFIG_IN_CHROOT)).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn numbers_a_jailer_must_not_take_are_refused() {
        for (uid, gid) in [(0, 30_007), (30_007, 0), (0, 0), (70_000, 30_007), (30_007, 70_000)] {
            assert!(jailer_arguments(ID, uid, gid, Path::new("/j"), "ms7", Path::new(CONFIG_IN_CHROOT)).is_err(), "{uid}:{gid}");
        }
        assert!(jailer_arguments(ID, 1, 1, Path::new("/j"), "ms7", Path::new(CONFIG_IN_CHROOT)).is_ok(), "the lowest unprivileged id is fine");
    }

    #[test]
    fn a_relative_path_or_a_bad_namespace_is_refused() {
        assert!(jailer_arguments(ID, 30_007, 30_007, Path::new("jail"), "ms7", Path::new(CONFIG_IN_CHROOT)).is_err());
        assert!(jailer_arguments(ID, 30_007, 30_007, Path::new("/jail"), "ms7", Path::new("config.json")).is_err());
        assert!(jailer_arguments(ID, 30_007, 30_007, Path::new("/jail"), "ms 7", Path::new(CONFIG_IN_CHROOT)).is_err(), "the namespace is a path for the jailer");
    }
}
