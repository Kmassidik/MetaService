//! Where one sandbox's own files live on the machine, and how they are made and taken away.
//!
//! Every path is built from a validated sandbox id, so an id that is not the contract's 20 lowercase letters and digits never reaches the filesystem: it
//! cannot climb out of the run directory, because it cannot be anything but 20 characters of `[a-z0-9]`.
//!
//! The layout under the run directory:
//!
//! ```text
//! <run>/<id>.slot          the slot this sandbox holds while it lives
//! <run>/<id>.pid           the Firecracker it started, so a runner that restarted can still stop it
//! <run>/<id>.console       its serial console, so a boot that fails says why
//! <run>/jail/<id>/root/    what the jailer chroots to: the kernel, the disk, the config, the API socket, a snapshot
//! ```
use crate::sandbox::firecracker::api;
use crate::sandbox::firecracker::{KERNEL_IN_CHROOT, ROOTFS_IN_CHROOT};
use crate::sandbox::record::is_sandbox_id;
use std::os::unix::fs::DirBuilderExt;
use std::path::{Path, PathBuf};

/// The one path Firecracker reads its config from, inside the chroot.
pub const CONFIG: &str = "/config.json";
/// Directories the runner makes for itself and for the sandboxes: only its own user reads them.
const PRIVATE_MODE: u32 = 0o700;

/// The run directory, and the paths one sandbox has inside it.
#[derive(Clone, Debug)]
pub struct Layout {
    root: PathBuf,
}

/// One sandbox's files, all of them built from its id.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Files {
    pub slot: PathBuf,
    pub pid: PathBuf,
    /// What Firecracker prints: the guest's serial console, which is how a boot that fails says why.
    pub console: PathBuf,
    /// The jailer's `--chroot-dir` for this sandbox: it makes `<jail>/<id>/root` under it.
    pub chroot_base: PathBuf,
    /// What the jailer chroots to, and what is filled with the kernel, the disk and the config.
    pub jail_root: PathBuf,
    /// The sandbox's own copy of the template's disk, written by [`crate::sandbox::firecracker::copy_disk_step`].
    pub disk: PathBuf,
    /// Firecracker's API socket, as the runner reaches it from outside the jail.
    pub api_socket: PathBuf,
    /// Where a snapshot of this sandbox goes: its device and CPU state, and its memory. Both stay under its own jail, so a delete takes them with it.
    pub snapshot_state: PathBuf,
    pub snapshot_memory: PathBuf,
}

impl Layout {
    pub fn new(root: PathBuf) -> Layout {
        Layout { root }
    }

    /// The paths for one sandbox, or a refusal when the id is not one the contract allows.
    pub fn files(&self, id: &str) -> Result<Files, String> {
        if !is_sandbox_id(id) {
            return Err("a sandbox id is 20 lowercase letters and digits".into());
        }
        let chroot_base = self.root.join("jail");
        let jail_root = chroot_base.join(id).join("root");
        Ok(Files {
            slot: self.root.join(format!("{id}.slot")),
            pid: self.root.join(format!("{id}.pid")),
            console: self.root.join(format!("{id}.console")),
            disk: in_jail(&jail_root, ROOTFS_IN_CHROOT),
            api_socket: in_jail(&jail_root, api::SOCKET_IN_CHROOT),
            snapshot_state: in_jail(&jail_root, api::SNAPSHOT_STATE_IN_CHROOT),
            snapshot_memory: in_jail(&jail_root, api::SNAPSHOT_MEMORY_IN_CHROOT),
            jail_root,
            chroot_base,
        })
    }

    pub fn create_root(&self) -> Result<(), String> {
        for directory in [self.root.clone(), self.root.join("jail")] {
            std::fs::DirBuilder::new().recursive(true).mode(PRIVATE_MODE).create(&directory).map_err(|e| format!("cannot make {}: {e}", directory.display()))?;
        }
        Ok(())
    }

    /// Fills the jail with what Firecracker needs from this build: the directory, the kernel (a hard link, it is only read) and the config. The disk is
    /// not copied here: that is a program ([`crate::sandbox::firecracker::copy_disk_step`]) and the runner runs it through its host, so a failed copy can
    /// be taken away before anything boots from it.
    pub fn prepare(&self, files: &Files, kernel: &Path, config: &str) -> Result<(), String> {
        std::fs::DirBuilder::new().recursive(true).mode(PRIVATE_MODE).create(&files.jail_root).map_err(|e| format!("cannot make the jail: {e}"))?;
        copy_shared(kernel, &files.jail_root.join(KERNEL_IN_CHROOT.trim_start_matches('/')))?;
        std::fs::write(files.jail_root.join(CONFIG.trim_start_matches('/')), config).map_err(|e| format!("cannot write the Firecracker config: {e}"))
    }

    /// Takes away a disk copy that did not finish, and says nothing when there is none: the template's own file is never touched, so the next start copies
    /// it again from the same place.
    pub fn remove_disk(&self, files: &Files) {
        remove_any(&files.disk);
    }

    /// The slot this sandbox holds, and whether it may reach the internet: both are what a delete has to name exactly, so both are written down before
    /// anything is made and survive a restart of the runner.
    pub fn save_slot(&self, files: &Files, slot: u8, internet: bool) -> Result<(), String> {
        let state = serde_json::json!({ "slot": slot, "internet": internet }).to_string();
        std::fs::write(&files.slot, state).map_err(|e| format!("cannot keep the slot: {e}"))
    }

    pub fn read_slot(&self, files: &Files) -> Option<(u8, bool)> {
        let state: serde_json::Value = serde_json::from_slice(&std::fs::read(&files.slot).ok()?).ok()?;
        let slot = u8::try_from(state["slot"].as_u64()?).ok().filter(|slot| *slot < crate::sandbox::firecracker::SLOTS)?;
        Some((slot, state["internet"].as_bool()?))
    }

    /// The sandboxes this run directory still knows, by slot: what a runner that restarted holds, so it never hands out a slot that a namespace still
    /// in use owns. A file that is not a slot is left alone.
    pub fn held(&self) -> Vec<(String, u8, bool)> {
        let Ok(entries) = std::fs::read_dir(&self.root) else { return Vec::new() };
        let mut held: Vec<(String, u8, bool)> = entries.flatten().filter_map(|entry| self.held_entry(&entry)).collect();
        held.sort_by_key(|(_, slot, _)| *slot);
        held
    }

    fn held_entry(&self, entry: &std::fs::DirEntry) -> Option<(String, u8, bool)> {
        let name = entry.file_name().to_string_lossy().into_owned();
        let id = name.strip_suffix(".slot")?;
        if !is_sandbox_id(id) {
            return None;
        }
        let (slot, internet) = self.read_slot(&self.files(id).ok()?)?;
        Some((id.to_string(), slot, internet))
    }

    /// Everything this sandbox had under the run directory: its jail (with its disk, its API socket and any snapshot), its console, its pid file and its
    /// slot file. Anything already gone is not an error.
    pub fn remove(&self, files: &Files) {
        if let Some(jail) = files.jail_root.parent() {
            remove_any(jail);
        }
        remove_any(&files.pid);
        remove_any(&files.slot);
        remove_any(&files.console);
    }
}

/// A path inside one sandbox's jail, from the path Firecracker sees after the chroot.
fn in_jail(jail_root: &Path, path_in_chroot: &str) -> PathBuf {
    jail_root.join(path_in_chroot.trim_start_matches('/'))
}

/// A hard link, or a copy when the two paths are on different filesystems. The kernel is only read, so either is right.
fn copy_shared(from: &Path, to: &Path) -> Result<(), String> {
    if std::fs::hard_link(from, to).is_ok() {
        return Ok(());
    }
    std::fs::copy(from, to).map(|_| ()).map_err(|e| format!("cannot place {}: {e}", from.display()))
}

/// Removes a file or a directory tree, and says nothing when it was not there: a delete is repeated freely.
fn remove_any(path: &Path) {
    if path.is_dir() {
        let _ = std::fs::remove_dir_all(path);
        return;
    }
    let _ = std::fs::remove_file(path);
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "abcdefghij0123456789";

    fn scratch(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("ms-layout-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        root
    }

    /// A template's kernel and disk, as the machine has them: two small files in a scratch directory.
    fn template(root: &Path) -> (PathBuf, PathBuf) {
        std::fs::DirBuilder::new().recursive(true).create(root.join("base")).unwrap();
        let (kernel, rootfs) = (root.join("base/vmlinux"), root.join("base/rootfs.ext4"));
        std::fs::write(&kernel, "kernel").unwrap();
        std::fs::write(&rootfs, "disk").unwrap();
        (kernel, rootfs)
    }

    #[test]
    fn a_sandbox_prepared_in_a_run_directory_holds_exactly_its_own_files() {
        let root = scratch("prepare");
        let (kernel, _) = template(&root);
        let layout = Layout::new(root.join("run"));
        layout.create_root().unwrap();
        let files = layout.files(ID).ok().unwrap();
        layout.prepare(&files, &kernel, r#"{"machine-config":{}}"#).unwrap();
        assert_eq!(std::fs::read_to_string(files.jail_root.join("vmlinux")).unwrap(), "kernel");
        assert_eq!(std::fs::read_to_string(files.jail_root.join("config.json")).unwrap(), r#"{"machine-config":{}}"#);
        assert_eq!(files.jail_root, root.join(format!("run/jail/{ID}/root")));
        assert!(!files.disk.exists(), "the disk is a step of its own, run by the runner");
        layout.save_slot(&files, 7, true).unwrap();
        assert_eq!(layout.read_slot(&files), Some((7, true)));
        layout.save_slot(&files, 7, false).unwrap();
        assert_eq!(layout.read_slot(&files), Some((7, false)), "the internet flag is kept with the slot");
        layout.remove(&files);
        assert!(!files.jail_root.exists() && !files.slot.exists());
        assert!(root.join("run").is_dir(), "the run directory itself stays");
        layout.remove(&files);
        assert_eq!(layout.read_slot(&files), None, "a sandbox with no slot file holds no slot");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn every_file_firecracker_uses_is_inside_this_sandboxs_own_jail() {
        let root = scratch("paths");
        let (_, rootfs) = template(&root);
        let layout = Layout::new(root.join("run"));
        let files = layout.files(ID).ok().unwrap();
        for path in [&files.disk, &files.api_socket, &files.snapshot_state, &files.snapshot_memory] {
            assert_eq!(path.parent(), Some(files.jail_root.as_path()), "{} is not in the sandbox's jail", path.display());
        }
        assert_ne!(files.disk, rootfs, "the sandbox never gets the template's own file");
        assert_eq!(files.api_socket, files.jail_root.join("firecracker.sock"), "Firecracker's socket, from outside the jail");
        assert_eq!(files.snapshot_state, files.jail_root.join("snapshot.state"));
        assert_eq!(files.snapshot_memory, files.jail_root.join("snapshot.mem"));
        assert_eq!(in_jail(&files.jail_root, "/vmlinux"), files.jail_root.join("vmlinux"), "a chroot path is the same path under the jail");
    }

    #[test]
    fn a_delete_takes_a_disk_and_a_snapshot_with_the_jail() {
        let root = scratch("snapshot");
        let (kernel, _) = template(&root);
        let layout = Layout::new(root.join("run"));
        let files = layout.files(ID).ok().unwrap();
        layout.prepare(&files, &kernel, "{}").unwrap();
        for path in [&files.disk, &files.snapshot_state, &files.snapshot_memory] {
            std::fs::write(path, "x").unwrap();
        }
        layout.remove(&files);
        assert!(!files.disk.exists() && !files.snapshot_state.exists() && !files.snapshot_memory.exists(), "a delete leaves no disk and no snapshot on the machine");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_disk_copy_that_failed_is_removed_and_the_template_is_still_there() {
        let root = scratch("halfcopy");
        let (_, rootfs) = template(&root);
        let layout = Layout::new(root.join("run"));
        let files = layout.files(ID).ok().unwrap();
        layout.prepare(&files, &template(&root).0, "{}").unwrap();
        std::fs::write(&files.disk, "half a disk").unwrap();
        layout.remove_disk(&files);
        assert!(!files.disk.exists(), "the half copy goes");
        assert_eq!(std::fs::read_to_string(&rootfs).unwrap(), "disk", "the template is only ever read");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_id_that_is_not_one_is_refused_before_any_path_is_built() {
        let layout = Layout::new(std::env::temp_dir().join("ms-layout-never"));
        for bad in ["../x", "a b", "--help", "", "ABCDEFGHIJ0123456789"] {
            assert!(layout.files(bad).is_err(), "{bad:?}");
        }
        assert!(!std::env::temp_dir().join("ms-layout-never").exists(), "a refused id touches nothing");
    }
}
