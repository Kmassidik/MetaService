//! The Firecracker backend, as architecture and pure builders: nothing here boots a microVM by itself.
//!
//! A sandbox is a microVM with its own kernel, run through Firecracker's `jailer` (sandbox/README.md, Safety). The steps that need root — a network
//! namespace, a tap, iptables rules, the jailer — live in the sandbox runner, which the helper reaches over a local socket; this module is what both
//! sides agree on:
//!
//! - [`jailer_arguments`]: the exact argv for one sandbox's jailer, built from a validated id and two numbers.
//! - [`config_json`]: the Firecracker JSON config, typed, with no user data pasted into a string.
//! - [`network_rules`]: the iptables rules that keep the office LAN, private ranges, the machine, other sandboxes, link-local and cloud metadata, and
//!   outgoing mail closed from inside a sandbox.
//!
//! Everything is a plain function of its arguments, so a hostile id or an out-of-range size is refused here, before anything runs, and every one of
//! them can be tested on a machine with no KVM and no root. There is no KVM machine in the session that wrote this slice, so no real microVM was
//! started: what is proven is the argument lists, the config and the rules, not a boot.
pub mod config;
pub mod engine;
pub mod jailer;
pub mod network;

pub use config::config_json;
pub use engine::FirecrackerSandboxEngine;
pub use jailer::start_step;

/// The pinned release `setup --yes` installs; never taken from a request.
pub const JAILER: &str = "/usr/local/bin/jailer";
pub const FIRECRACKER: &str = "/usr/local/bin/firecracker";
/// The guest kernel and the base template's disk, as `setup --yes` pins them on the machine.
pub const KERNEL: &str = "/var/lib/metaservice-sandbox/base/vmlinux";
pub const ROOTFS: &str = "/var/lib/metaservice-sandbox/base/rootfs.ext4";
/// The kernel, the disk and the vsock socket as Firecracker sees them: the jailer chroots before it starts, so these are its whole filesystem.
pub const KERNEL_IN_CHROOT: &str = "/vmlinux";
pub const ROOTFS_IN_CHROOT: &str = "/rootfs.ext4";
pub const VSOCK_IN_CHROOT: &str = "/vsock.sock";
/// Where the runner keeps the live sandboxes' own files: slots, pids, chroots. Root only.
pub const RUN_DIR: &str = "/run/metaservice-sandbox";
/// The runner's socket. Only the helper's user may open it (`setup --yes` sets the group and mode).
pub const SOCKET: &str = "/run/metaservice-sandbox/runner.sock";
/// The interface a sandbox reaches the internet through. Named at the machine; a default, not a rule.
pub const UPLINK: &str = "eth0";
/// How many sandboxes may exist at once, and so how many slots, uids and subnets exist. The helper's own default is 32.
pub const SLOTS: u8 = 64;
/// The first uid and gid a sandbox gets: `UID_BASE + slot`, so no two live sandboxes share one. `setup --yes` makes the users.
pub const UID_BASE: u32 = 30_000;
/// The kernel arguments every sandbox boots with: a serial console, no PCI probing, and a guest address baked into the template (clones share it, so
/// each sandbox gets its own namespace instead). Not taken from a request.
pub const BOOT_ARGS: &str = "console=ttyS0 reboot=k panic=1 pci=off nomodules";

/// One program to run, as a program and its arguments: never a shell, never a command line built out of text from a caller.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Step {
    pub program: &'static str,
    pub arguments: Vec<String>,
}

impl Step {
    pub fn new(program: &'static str, arguments: Vec<String>) -> Step {
        Step { program, arguments }
    }

    /// The step as an operator would type it, for the log only.
    pub fn describe(&self) -> String {
        format!("{} {}", self.program, self.arguments.join(" "))
    }
}

/// The user and group a sandbox's jailer drops to, and the name the tap is handed to. `setup --yes` makes one user per slot; until then the jailer and
/// the tap fail, and the runner says so instead of starting anything.
pub fn sandbox_user(slot: u8) -> String {
    format!("mssbx{slot}")
}
