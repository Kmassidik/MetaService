//! The Firecracker JSON config for one sandbox, as a typed value: every field is written by `serde_json`, so no id, path or number is ever pasted into
//! a string, and every number is checked against the contract's own bounds first.
//!
//! The paths are the ones Firecracker sees after the jailer's chroot (`/vmlinux`, `/rootfs.ext4`, `/vsock.sock`), because the jailer chroots before it
//! starts Firecracker. Nothing here boots anything: the config is a value, and the runner is what writes and starts it.
use super::BOOT_ARGS;
use crate::sandbox::record::{MAX_RAM_MB, MAX_VCPU, MIN_RAM_MB, MIN_VCPU};
use serde_json::{json, Value};
use std::path::Path;

/// The guest sees this interface; the tap behind it is `tap0` inside the sandbox's own namespace.
const IFACE_ID: &str = "net0";
const DRIVE_ID: &str = "rootfs";
/// One MAC for every sandbox: each has its own namespace and tap, so no two are ever on the same link.
const GUEST_MAC: &str = "AA:FC:00:00:00:01";
/// A guest CID is a 32-bit number, and 0, 1 and 2 belong to the host and the hypervisor.
const MIN_GUEST_CID: u32 = 3;
const MAX_GUEST_CID: u32 = 4_294_967_295;
const LOG_LEVEL: &str = "Info";
/// The longest device name the kernel takes: the tap Firecracker opens.
const DEVICE_NAME_MAX: usize = 15;

/// The config: vCPU count, memory, the kernel, the root disk, the tap, and where the vsock answers. `vsock_path` is written by the helper's side of
/// Firecracker's API later; this slice only lays it out.
pub fn config_json(vcpu: u32, ram_mb: u64, kernel: &Path, rootfs: &Path, tap: &str, vsock_path: &Path, guest_cid: u32) -> Result<String, String> {
    check_vcpu(vcpu)?;
    check_ram(ram_mb)?;
    check_guest_cid(guest_cid)?;
    if !is_device_name(tap) {
        return Err(format!("{tap:?} is not a tap device name"));
    }
    let kernel = in_chroot(kernel)?;
    let rootfs = in_chroot(rootfs)?;
    let vsock_path = in_chroot(vsock_path)?;
    let config = json!({
        "boot-source": { "kernel_image_path": kernel, "boot_args": BOOT_ARGS },
        "drives": [{ "drive_id": DRIVE_ID, "path_on_host": rootfs, "is_root_device": true, "is_read_only": false }],
        "machine-config": { "vcpu_count": vcpu, "mem_size_mib": ram_mb, "smt": false },
        "network-interfaces": [{ "iface_id": IFACE_ID, "guest_mac": GUEST_MAC, "host_dev_name": tap }],
        "vsock": { "guest_cid": guest_cid, "uds_path": vsock_path },
        "logger": { "log_path": "/firecracker.log", "level": LOG_LEVEL, "show_level": true, "show_log_origin": false },
    });
    Ok(Value::to_string(&config))
}

fn check_vcpu(vcpu: u32) -> Result<(), String> {
    if (MIN_VCPU..=MAX_VCPU).contains(&u64::from(vcpu)) {
        return Ok(());
    }
    Err(format!("vcpu_count must be {MIN_VCPU} to {MAX_VCPU}"))
}

fn check_ram(ram_mb: u64) -> Result<(), String> {
    if (MIN_RAM_MB..=MAX_RAM_MB).contains(&ram_mb) {
        return Ok(());
    }
    Err(format!("mem_size_mib must be {MIN_RAM_MB} to {MAX_RAM_MB}"))
}

fn check_guest_cid(guest_cid: u32) -> Result<(), String> {
    if (MIN_GUEST_CID..=MAX_GUEST_CID).contains(&guest_cid) {
        return Ok(());
    }
    Err(format!("guest_cid must be {MIN_GUEST_CID} or more: 0, 1 and 2 belong to the host"))
}

/// A path as Firecracker reads it: absolute, and text this machine can hand to a program.
fn in_chroot(path: &Path) -> Result<String, String> {
    if !path.is_absolute() {
        return Err(format!("{} must be an absolute path inside the chroot", path.display()));
    }
    let text = path.to_str().ok_or_else(|| format!("{} is not a path this machine can use", path.display()))?;
    if text.contains('\0') {
        return Err("a path cannot hold a NUL byte".into());
    }
    Ok(text.to_string())
}

/// A device name the kernel takes: letters, digits, `-`, `_` and `.`, at most 15 characters, starting with a letter or a digit.
fn is_device_name(name: &str) -> bool {
    let allowed = |character: char| character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.');
    let Some(first) = name.chars().next() else { return false };
    first.is_ascii_alphanumeric() && name.len() <= DEVICE_NAME_MAX && name.chars().all(allowed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config() -> Value {
        let text = config_json(2, 512, Path::new("/vmlinux"), Path::new("/rootfs.ext4"), "tap0", Path::new("/vsock.sock"), 10).ok().unwrap();
        serde_json::from_str(&text).expect("the builder writes JSON")
    }

    #[test]
    fn a_sandbox_config_carries_exactly_the_fields_firecracker_needs() {
        let config = config();
        assert_eq!(config["boot-source"]["kernel_image_path"], "/vmlinux");
        assert_eq!(config["boot-source"]["boot_args"], BOOT_ARGS);
        assert_eq!(config["machine-config"], json!({"vcpu_count": 2, "mem_size_mib": 512, "smt": false}));
        assert_eq!(config["drives"][0], json!({"drive_id": "rootfs", "path_on_host": "/rootfs.ext4", "is_root_device": true, "is_read_only": false}));
        assert_eq!(config["network-interfaces"][0], json!({"iface_id": "net0", "guest_mac": "AA:FC:00:00:00:01", "host_dev_name": "tap0"}));
        assert_eq!(config["vsock"], json!({"guest_cid": 10, "uds_path": "/vsock.sock"}));
        assert_eq!(config["logger"]["level"], "Info");
        assert_eq!(config.as_object().unwrap().len(), 6, "and nothing else");
        assert_eq!(config_json(2, 512, Path::new("/vmlinux"), Path::new("/rootfs.ext4"), "tap0", Path::new("/vsock.sock"), 10), Ok(Value::to_string(&config)));
    }

    #[test]
    fn a_size_the_contract_does_not_allow_is_refused() {
        let paths = (Path::new("/vmlinux"), Path::new("/rootfs.ext4"), Path::new("/vsock.sock"));
        for (vcpu, ram_mb) in [(0, 512), (33, 512), (2, 0), (2, MIN_RAM_MB - 1), (2, MAX_RAM_MB + 1)] {
            assert!(config_json(vcpu, ram_mb, paths.0, paths.1, "tap0", paths.2, 3).is_err(), "{vcpu} vCPU and {ram_mb} MB");
        }
        assert!(config_json(MAX_VCPU as u32, MAX_RAM_MB, paths.0, paths.1, "tap0", paths.2, 3).is_ok(), "the largest the contract allows is allowed here");
    }

    #[test]
    fn a_hostile_tap_or_a_relative_path_is_refused() {
        let paths = (Path::new("/vmlinux"), Path::new("/rootfs.ext4"), Path::new("/vsock.sock"));
        for tap in ["", "tap 0", "../tap0", "--help", "averylongtapdevicename"] {
            assert!(config_json(2, 512, paths.0, paths.1, tap, paths.2, 3).is_err(), "{tap:?}");
        }
        assert!(config_json(2, 512, Path::new("vmlinux"), paths.1, "tap0", paths.2, 3).is_err());
        assert!(config_json(2, 512, paths.0, Path::new("rootfs.ext4"), "tap0", paths.2, 3).is_err());
        assert!(config_json(2, 512, paths.0, paths.1, "tap0", Path::new("vsock.sock"), 3).is_err());
    }

    #[test]
    fn a_guest_cid_below_three_is_refused() {
        let paths = (Path::new("/vmlinux"), Path::new("/rootfs.ext4"), Path::new("/vsock.sock"));
        for cid in [0, 1, 2] {
            assert!(config_json(2, 512, paths.0, paths.1, "tap0", paths.2, cid).is_err(), "cid {cid}");
        }
        assert!(config_json(2, 512, paths.0, paths.1, "tap0", paths.2, 3).is_ok());
    }
}
