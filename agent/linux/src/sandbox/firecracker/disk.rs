//! One sandbox's own disk, copied from the template: a reflink where the filesystem can, a full copy where it cannot.
//!
//! A sandbox may write anywhere in its root disk, so its disk is its own: handing Firecracker the template's file, or a hard link to it, would let one
//! sandbox — or one bad `mkfs` — change the template every other sandbox is made from.
//!
//! `cp --reflink=auto` is the whole of the rule: on a filesystem with reflinks (XFS, btrfs) the copy costs a new inode and no blocks, and anywhere else
//! `auto` quietly makes a full copy. So there is one step and one flag, not a reflink attempt and a hand-written fallback that could disagree with it.
//!
//! The template is only ever read. When the copy fails the partial file is removed by the runner, and the template is exactly as it was.
use super::Step;
use std::path::Path;

/// `cp` from the machine's own path list, never from a request.
pub const CP: &str = "/bin/cp";
/// The flag that makes one step cover both filesystems: a reflink where that is possible, a full copy where it is not.
pub const REFLINK_ARGUMENT: &str = "--reflink=auto";

/// The step that gives one sandbox its disk, from the template's file to the sandbox's own, and nothing else: `--` before the two paths, so neither can
/// be read as a flag.
pub fn copy_disk_step(template: &Path, sandbox_disk: &Path) -> Result<Step, String> {
    let from = path_argument(template)?;
    let to = path_argument(sandbox_disk)?;
    Ok(Step::new(CP, vec![REFLINK_ARGUMENT.to_string(), "--".to_string(), from, to]))
}

/// A path as an argument: absolute (the runner's own directories are), text, and without a NUL, which no program can be given.
fn path_argument(path: &Path) -> Result<String, String> {
    if !path.is_absolute() {
        return Err(format!("{} must be an absolute path", path.display()));
    }
    let text = path.to_str().ok_or_else(|| format!("{} is not a path this machine can use", path.display()))?;
    if text.contains('\0') {
        return Err("a path cannot hold a NUL byte".into());
    }
    Ok(text.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_disk_copy_is_one_fixed_argument_list() {
        let step = copy_disk_step(Path::new("/var/lib/metaservice-sandbox/base/rootfs.ext4"), Path::new("/run/metaservice-sandbox/jail/abcdefghij0123456789/root/rootfs.ext4")).ok().unwrap();
        assert_eq!(step.program, "/bin/cp");
        assert_eq!(
            step.arguments,
            ["--reflink=auto", "--", "/var/lib/metaservice-sandbox/base/rootfs.ext4", "/run/metaservice-sandbox/jail/abcdefghij0123456789/root/rootfs.ext4"].map(String::from)
        );
        assert_eq!(step.describe(), "/bin/cp --reflink=auto -- /var/lib/metaservice-sandbox/base/rootfs.ext4 /run/metaservice-sandbox/jail/abcdefghij0123456789/root/rootfs.ext4");
    }

    #[test]
    fn a_path_a_program_cannot_be_given_is_refused_before_anything_runs() {
        for (template, disk) in [("rootfs.ext4", "/run/disk"), ("/template", "disk"), ("/template", "")] {
            assert!(copy_disk_step(Path::new(template), Path::new(disk)).is_err(), "{template:?} to {disk:?}");
        }
    }
}
