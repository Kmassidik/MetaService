//! The engine that really runs sandboxes: Firecracker through the jailer, made by the root runner, reached over its local socket.
//!
//! The engine itself holds no root and runs no program: every step that touches the machine is a request to the runner, and the runner's list is fixed.
//! That is why a helper whose runner is missing, whose KVM is off or whose base template was never built says "cannot run sandboxes" ([`connect`] fails,
//! and the helper answers as it does with no engine at all: `capabilities.sandbox` false, every sandbox route a 404) instead of failing.
//!
//! What is not proven here: whether a microVM really boots. This slice was written on a machine with no KVM and no Firecracker, so what its tests prove is
//! the order and the content of the requests, not a running sandbox.
use crate::sandbox::engine::{Limits, Sample, SandboxEngine, Template, BASE_TEMPLATE};
use crate::sandbox::record::{Sandbox, TEMPLATE_READY};
use crate::sandbox::runner::Runner;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::UNIX_EPOCH;

/// The engine's name in the facts.
pub const NAME: &str = "firecracker";
/// Which build of the base template this engine serves. The template build that changes it comes with snapshots.
const BASE_BUILD: &str = "1";
/// The base template's own size, as the contract reports it, until a template is really built and measured.
const BASE_SIZE_MB: u64 = 1024;
/// Firecracker's own device: no microVM without it.
const KVM: &str = "/dev/kvm";

/// What this machine must have, in one place, so a test can point it at anything: KVM, the pinned kernel, the base template's disk.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Machine {
    pub kvm: PathBuf,
    pub kernel: PathBuf,
    pub rootfs: PathBuf,
}

impl Default for Machine {
    fn default() -> Machine {
        Machine { kvm: KVM.into(), kernel: super::KERNEL.into(), rootfs: super::ROOTFS.into() }
    }
}

impl Machine {
    /// Every piece of what a sandbox boots from, named. The first one missing is the reason this helper cannot run sandboxes.
    fn missing(&self) -> Option<(&'static str, PathBuf)> {
        [("KVM", &self.kvm), ("the guest kernel", &self.kernel), ("the base template's disk", &self.rootfs)]
            .into_iter()
            .find(|(_, path)| !path.exists())
            .map(|(what, path)| (what, path.clone()))
    }
}

/// Firecracker, through the runner.
pub struct FirecrackerSandboxEngine {
    runner: Arc<dyn Runner>,
    limits: Limits,
    machine: Machine,
    /// The runner's version: the version of the thing that runs the sandboxes, which is what the facts can honestly say.
    version: String,
}

impl FirecrackerSandboxEngine {
    /// Connects only when this machine can really run sandboxes: the runner answers, and KVM, the kernel and the base disk are there. Anything else is
    /// the plain reason the helper logs before it reports that it cannot run sandboxes.
    pub fn connect(runner: Arc<dyn Runner>, limits: Limits, machine: Machine) -> Result<FirecrackerSandboxEngine, String> {
        let version = runner.version()?;
        if let Some((what, path)) = machine.missing() {
            return Err(format!("{what} is not on this machine ({}), so no sandbox can start", path.display()));
        }
        Ok(FirecrackerSandboxEngine { runner, limits, machine, version })
    }
}

impl SandboxEngine for FirecrackerSandboxEngine {
    fn name(&self) -> &'static str {
        NAME
    }

    fn version(&self) -> Option<String> {
        Some(self.version.clone())
    }

    fn limits(&self) -> Limits {
        self.limits
    }

    /// `base`, ready exactly while the kernel and the disk it boots from are still there. The build time is the disk's own, not the moment it was asked.
    fn templates(&self) -> Vec<Template> {
        let ready = self.machine.missing().is_none();
        let built_at = std::fs::metadata(&self.machine.rootfs).and_then(|metadata| metadata.modified()).ok().and_then(|modified| modified.duration_since(UNIX_EPOCH).ok());
        let state = if ready { TEMPLATE_READY } else { "failed" };
        vec![Template { id: BASE_TEMPLATE.into(), build: BASE_BUILD.into(), state, built_at: built_at.map(|since| since.as_secs()), size_mb: BASE_SIZE_MB, message: None }]
    }

    /// The network first, then Firecracker from it. A start that fails is not left half done: the network goes back out, so a create that fails leaves
    /// nothing behind for the sweep to find.
    fn create(&self, sandbox: &Sandbox) -> Result<(), String> {
        self.runner.create_network(&sandbox.id, sandbox.internet)?;
        match self.runner.start(&sandbox.id, sandbox.vcpu, sandbox.ram_mb) {
            Ok(()) => Ok(()),
            Err(cause) => {
                if let Err(left) = self.runner.delete_network(&sandbox.id) {
                    eprintln!("sandbox {}: its network could not be taken back after a failed start: {left}", sandbox.id);
                }
                Err(cause)
            }
        }
    }

    fn stop(&self, id: &str) -> Result<(), String> {
        self.runner.stop(id)
    }

    /// Firecracker's own pause, through its API socket in the sandbox's jail. Nothing about it lives here: the runner has the socket, and the record of
    /// what is paused is the helper's.
    fn pause(&self, id: &str) -> Result<(), String> {
        self.runner.pause(id)
    }

    fn resume(&self, id: &str) -> Result<(), String> {
        self.runner.resume(id)
    }

    /// The process and then everything it had. The network goes even when the stop failed, so no namespace outlives its sandbox; the first thing that
    /// went wrong is what the helper logs.
    fn delete(&self, id: &str) -> Result<(), String> {
        let stopped = self.runner.stop(id);
        let forgotten = self.runner.delete_network(id);
        stopped.and(forgotten)
    }

    /// No readings yet: they come from the cgroup the jailer makes, which the runner will report in a later slice. An empty list says "nothing measured"
    /// where a zero would say "nothing used", and a sandbox is not idle just because nobody measured it.
    fn metrics(&self, _sandbox: &Sandbox, _now: u64) -> Vec<Sample> {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sandbox::record::CreateRequest;
    use crate::sandbox::runner::FakeRunner;
    use serde_json::json;

    const ID: &str = "abcdefghij0123456789";

    fn limits() -> Limits {
        Limits { max_running: 4, max_vcpu: 8, max_ram_mb: 4096, max_disk_mb: 8192 }
    }

    /// A machine whose kernel and disk are there, and whose KVM is whatever the test made: three files in a scratch directory.
    fn machine(name: &str, kvm: bool) -> Machine {
        let root = std::env::temp_dir().join(format!("ms-engine-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let (kernel, rootfs) = (root.join("vmlinux"), root.join("rootfs.ext4"));
        std::fs::write(&kernel, "kernel").unwrap();
        std::fs::write(&rootfs, "disk").unwrap();
        if kvm {
            std::fs::write(root.join("kvm"), "").unwrap();
        }
        Machine { kvm: root.join("kvm"), kernel, rootfs }
    }

    fn sandbox() -> Sandbox {
        let body = json!({"id": ID, "template": "base", "vcpu": 2, "ram_mb": 512, "disk_mb": 1024, "end_at": "2027-01-01T00:00:00Z",
            "on_end": "kill", "internet": true, "env_vars": {}, "access_token": "t".repeat(40)});
        let request = CreateRequest::parse(body.to_string().as_bytes()).ok().unwrap();
        Sandbox::new(&request, BASE_BUILD.into(), "fingerprint".into(), 1_792_834_200)
    }

    #[test]
    fn a_machine_that_cannot_run_sandboxes_says_so_instead_of_failing() {
        let unreachable = FirecrackerSandboxEngine::connect(FakeRunner::refusing("no runner"), limits(), machine("noplace", true));
        assert_eq!(unreachable.err(), Some("no runner".into()));
        let no_kvm = FirecrackerSandboxEngine::connect(FakeRunner::new(), limits(), machine("nokvm", false)).err();
        assert!(no_kvm.as_deref().is_some_and(|reason| reason.contains("KVM")), "{no_kvm:?}");
        let missing_disk = FirecrackerSandboxEngine::connect(FakeRunner::new(), limits(), Machine { rootfs: "/nowhere/rootfs.ext4".into(), ..machine("nodisk", true) }).err();
        assert!(missing_disk.as_deref().is_some_and(|reason| reason.contains("disk")), "{missing_disk:?}");
        let engine = FirecrackerSandboxEngine::connect(FakeRunner::new(), limits(), machine("good", true)).ok().unwrap();
        assert_eq!((engine.name(), engine.version()), (NAME, Some("0.1.0".into())));
        assert!(engine.templates()[0].ready(), "the base template is there");
    }

    #[test]
    fn a_sandbox_is_a_network_then_firecracker_on_it() {
        let runner = FakeRunner::new();
        let engine = FirecrackerSandboxEngine::connect(runner.clone(), limits(), machine("create", true)).ok().unwrap();
        assert_eq!(engine.create(&sandbox()), Ok(()));
        assert_eq!(runner.calls()[1..], ["create-network abcdefghij0123456789 true", "start abcdefghij0123456789 2 512"]);
        assert_eq!(engine.delete(ID), Ok(()));
        assert_eq!(runner.calls()[3..], ["stop abcdefghij0123456789", "delete-network abcdefghij0123456789"]);
    }

    #[test]
    fn a_start_that_fails_takes_its_network_back_out() {
        let runner = FakeRunner::new();
        let engine = FirecrackerSandboxEngine::connect(runner.clone(), limits(), machine("cleanup", true)).ok().unwrap();
        runner.refuse_when("start", "no Firecracker on this machine");
        assert_eq!(engine.create(&sandbox()).err(), Some("no Firecracker on this machine".into()));
        assert_eq!(runner.calls()[1..], ["create-network abcdefghij0123456789 true", "start abcdefghij0123456789 2 512", "delete-network abcdefghij0123456789"]);
    }

    #[test]
    fn nothing_measured_is_not_the_same_as_nothing_used() {
        let engine = FirecrackerSandboxEngine::connect(FakeRunner::new(), limits(), machine("metrics", true)).ok().unwrap();
        assert!(engine.metrics(&sandbox(), 1_792_834_300).is_empty());
        assert_eq!(engine.limits().max_running, 4);
    }

    #[test]
    fn a_pause_and_a_resume_are_runner_requests_and_nothing_else() {
        let runner = FakeRunner::new();
        let engine = FirecrackerSandboxEngine::connect(runner.clone(), limits(), machine("pause", true)).ok().unwrap();
        assert_eq!(engine.pause(ID), Ok(()));
        assert_eq!(engine.resume(ID), Ok(()));
        assert_eq!(runner.calls()[1..], ["pause abcdefghij0123456789", "resume abcdefghij0123456789"]);
        runner.refuse_when("pause", "no Firecracker API on this sandbox");
        assert_eq!(engine.pause(ID).err(), Some("no Firecracker API on this sandbox".into()), "the runner's reason is passed on as it is");
    }
}
