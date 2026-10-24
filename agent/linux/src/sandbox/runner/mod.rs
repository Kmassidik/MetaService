//! The sandbox runner: the same program in another mode (`--sandbox-runner`), as root, on a local socket, with a fixed list of requests.
//!
//! Firecracker's jailer, network namespaces, tap devices and firewall rules need root, and the helper must not have it (sandbox/README.md). So the runner
//! owns those steps and nothing else, and the helper talks to it in the wire format of [`protocol`]: **one JSON request per line, one answer per line**,
//! six requests in all — `health`, `create-network`, `delete-network`, `start`, `stop`. There is no shell and no free-form argv: an id is the contract's
//! 20 lowercase letters and digits, a size is a number in the contract's bounds, and every program, flag and path is a constant of this build.
//!
//! What the runner is handed at the machine: the socket, the run directory, the uplink interface, and the pinned kernel and base disk. What it asks the
//! machine to do goes through [`Host`], so the whole request list can be exercised with a host that records instead of one that runs.
mod client;
mod host;
mod layout;
mod protocol;
#[cfg(test)]
mod tests;

pub use client::RunnerClient;
pub use host::{Host, RealHost};
pub use layout::{Files, Layout};
pub use protocol::{PROTOCOL, Request, Reply};


#[cfg(test)]
pub use client::FakeRunner;

use crate::sandbox::firecracker::network::{create_steps, delete_steps, network_rule_deletions, network_rules, owner, Network};
use crate::sandbox::firecracker::{config_json, start_step, Step, KERNEL_IN_CHROOT, ROOTFS_IN_CHROOT, SLOTS, VSOCK_IN_CHROOT};
use crate::sandbox::firecracker::jailer::CONFIG_IN_CHROOT;
use std::collections::BTreeMap;
use std::io::{BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

/// What the helper needs from whatever makes sandboxes, as the runner sees it: five calls, each one a line.
pub trait Runner: Send + Sync {
    /// The runner's own version, or a plain reason it cannot be reached.
    fn version(&self) -> Result<String, String>;
    fn create_network(&self, id: &str, internet: bool) -> Result<(), String>;
    fn delete_network(&self, id: &str) -> Result<(), String>;
    fn start(&self, id: &str, vcpu: u32, ram_mb: u64) -> Result<(), String>;
    fn stop(&self, id: &str) -> Result<(), String>;
}

/// What the runner is told when it is installed on the machine: where its socket and files go, which interface a sandbox may use, and the pinned kernel
/// and base disk. Never from a request.
#[derive(Clone, Debug)]
pub struct Settings {
    pub socket: PathBuf,
    pub run_dir: PathBuf,
    pub uplink: String,
    pub kernel: PathBuf,
    pub rootfs: PathBuf,
}

impl Default for Settings {
    fn default() -> Settings {
        Settings { socket: crate::sandbox::firecracker::SOCKET.into(), run_dir: crate::sandbox::firecracker::RUN_DIR.into(), uplink: crate::sandbox::firecracker::UPLINK.into(),
            kernel: crate::sandbox::firecracker::KERNEL.into(), rootfs: crate::sandbox::firecracker::ROOTFS.into() }
    }
}

/// The runner: the sockets, the slots its sandboxes hold, and the machine behind [`Host`].
pub struct Server {
    settings: Settings,
    layout: Layout,
    slots: Slots,
    host: Arc<dyn Host>,
}

impl Server {
    /// A runner that does things to the machine.
    pub fn new(settings: Settings) -> Result<Server, String> {
        Self::with_host(settings, Arc::new(RealHost::default()))
    }

    pub fn with_host(settings: Settings, host: Arc<dyn Host>) -> Result<Server, String> {
        let layout = Layout::new(settings.run_dir.clone());
        layout.create_root()?;
        let slots = Slots::seeded(layout.held());
        Ok(Server { settings, layout, slots, host })
    }

    /// Listens until the process is stopped. One connection at a time, one request per line: the steps are short, and a runner that does one thing at a
    /// time cannot have two creates pick the same slot.
    pub fn listen(&self) -> Result<(), String> {
        let _ = std::fs::remove_file(&self.settings.socket);
        let listener = UnixListener::bind(&self.settings.socket).map_err(|e| format!("cannot listen on {}: {e}", self.settings.socket.display()))?;
        let mode = std::fs::Permissions::from_mode(SOCKET_MODE);
        std::fs::set_permissions(&self.settings.socket, mode).map_err(|e| format!("cannot set the socket's mode: {e}"))?;
        println!("sandbox runner listening on {} (uplink {}, protocol {PROTOCOL})", self.settings.socket.display(), self.settings.uplink);
        for stream in listener.incoming() {
            match stream {
                Ok(stream) => self.connection(stream),
                Err(cause) => eprintln!("sandbox runner: a connection did not arrive: {cause}"),
            }
        }
        Ok(())
    }

    /// One connection: as many one-line requests as the caller sends, each answered on its own line. A bad request is refused and the connection stays
    /// open, so a caller can see the reason; a line that is too long ends the connection instead of being read forever.
    pub fn connection(&self, stream: UnixStream) {
        let mut answers = match stream.try_clone() {
            Ok(answers) => answers,
            Err(cause) => return eprintln!("sandbox runner: a connection cannot be answered: {cause}"),
        };
        let mut requests = BufReader::new(stream);
        loop {
            let line = match request_line(&mut requests) {
                Ok(Some(line)) => line,
                Ok(None) => return,
                Err(cause) => return self.refuse_and_close(&mut answers, &cause),
            };
            let reply = match Request::parse(&line) {
                Ok(request) => self.answer(request),
                Err(cause) => protocol::failure(&cause),
            };
            if write_reply(&mut answers, &reply).is_err() {
                return;
            }
        }
    }

    fn refuse_and_close(&self, answers: &mut UnixStream, cause: &str) {
        eprintln!("sandbox runner: {cause}");
        let _ = write_reply(answers, &protocol::failure(cause));
    }

    /// One request, answered. The reason never leaves this process as anything but a short line, and a step's own paths stay in its log.
    fn answer(&self, request: Request) -> Reply {
        let handled = match request {
            Request::Health => Ok(Reply::Health { version: crate::config::VERSION.into(), protocol: PROTOCOL }),
            Request::CreateNetwork { id, internet } => self.create_network(&id, internet),
            Request::DeleteNetwork { id } => self.delete_network(&id),
            Request::Start { id, vcpu, ram_mb } => self.start(&id, vcpu, ram_mb),
            Request::Stop { id } => self.stop(&id),
        };
        match handled {
            Ok(reply) => reply,
            Err(cause) => {
                eprintln!("sandbox runner: {cause}");
                protocol::failure(&cause)
            }
        }
    }

    /// The namespace, the tap, the veth pair and the firewall rules. A create that fails half way takes back what it made, so a sandbox that never
    /// started leaves no namespace, no tap and no rule behind.
    fn create_network(&self, id: &str, internet: bool) -> Result<Reply, String> {
        let files = self.layout.files(id)?;
        if let Some((slot, _)) = self.slots.get(id) {
            // It is already there: a retried create changes nothing.
            return Ok(Reply::Done { slot: Some(slot), steps: 0 });
        }
        let slot = self.slots.free().ok_or_else(|| format!("every one of this machine's {SLOTS} sandbox slots is taken"))?;
        let net = Network::of(slot);
        let steps = self.creation_steps(net, internet)?;
        self.layout.save_slot(&files, slot, internet)?;
        self.slots.hold(id, slot, internet);
        if let Err(cause) = self.run_all(&steps) {
            self.slots.release(id);
            self.forget(&files, net, internet);
            return Err(cause);
        }
        Ok(Reply::Done { slot: Some(slot), steps: steps.len() })
    }

    fn creation_steps(&self, net: Network, internet: bool) -> Result<Vec<Step>, String> {
        let mut steps = create_steps(net);
        steps.extend(network_rules(net, &self.settings.uplink, internet)?);
        Ok(steps)
    }

    /// Everything the sandbox had on the network, out again. A sandbox this runner has no slot for is answered the same way: what is left is taken
    /// away, and a repeated delete changes nothing.
    fn delete_network(&self, id: &str) -> Result<Reply, String> {
        let files = self.layout.files(id)?;
        let Some((slot, internet)) = self.slots.release(id) else {
            self.layout.remove(&files);
            return Ok(Reply::Done { slot: None, steps: 0 });
        };
        let net = Network::of(slot);
        self.forget(&files, net, internet);
        Ok(Reply::Done { slot: Some(slot), steps: 1 })
    }

    /// Firecracker through the jailer, from the network the sandbox already has. A sandbox with no network is refused rather than started unreachable.
    fn start(&self, id: &str, vcpu: u32, ram_mb: u64) -> Result<Reply, String> {
        let files = self.layout.files(id)?;
        let (slot, _) = self.slots.get(id).ok_or("this sandbox has no network yet: create it first")?;
        let net = Network::of(slot);
        let (_, uid, gid) = owner(slot);
        let config = config_json(vcpu, ram_mb, Path::new(KERNEL_IN_CHROOT), Path::new(ROOTFS_IN_CHROOT), net.tap(), Path::new(VSOCK_IN_CHROOT), guest_cid(slot))?;
        self.layout.prepare(&files, &self.settings.kernel, &self.settings.rootfs, &config)?;
        let step = start_step(id, uid, gid, &files.chroot_base, &net.namespace(), Path::new(CONFIG_IN_CHROOT))?;
        self.host.spawn(&files, &step)?;
        Ok(Reply::Done { slot: Some(slot), steps: 1 })
    }

    fn stop(&self, id: &str) -> Result<Reply, String> {
        let files = self.layout.files(id)?;
        self.host.stop(&files)?;
        Ok(Reply::Done { slot: self.slots.get(id).map(|(slot, _)| slot), steps: 1 })
    }

    /// Takes the network away and frees the slot, whatever the caller says next. Each step is tried whether or not the last one found anything, and the
    /// ones that were already gone are logged and left: a delete is repeated freely.
    fn forget(&self, files: &Files, net: Network, internet: bool) {
        let mut steps = delete_steps(net);
        match network_rule_deletions(net, &self.settings.uplink, internet) {
            Ok(deletions) => steps.extend(deletions),
            Err(cause) => eprintln!("sandbox runner: the rules of {} cannot be named: {cause}", net.namespace()),
        }
        for step in steps {
            if let Err(cause) = self.host.run(&step) {
                eprintln!("sandbox runner: {} did not go through: {cause}", step.describe());
            }
        }
        self.layout.remove(files);
    }

    /// Every step, in order, stopping at the first one that fails: what comes after it would be built on something that is not there.
    fn run_all(&self, steps: &[Step]) -> Result<(), String> {
        steps.iter().try_for_each(|step| self.host.run(step).map_err(|cause| format!("{}: {cause}", step.describe())))
    }
}

/// The guest's vsock id: unique per live sandbox, and 0, 1 and 2 belong to the host and the hypervisor.
fn guest_cid(slot: u8) -> u32 {
    u32::from(FIRST_GUEST_CID + slot)
}

/// Which slots are held, by which sandbox, and whether that sandbox may reach the internet (its rules are what a delete has to name exactly).
#[derive(Default)]
struct Slots {
    held: Mutex<BTreeMap<String, (u8, bool)>>,
}

impl Slots {
    /// The slots a runner that restarted still has sandboxes in: read from the run directory, because a namespace that is still there owns its slot.
    fn seeded(held: Vec<(String, u8, bool)>) -> Slots {
        Slots { held: Mutex::new(held.into_iter().map(|(id, slot, internet)| (id, (slot, internet))).collect()) }
    }

    fn get(&self, id: &str) -> Option<(u8, bool)> {
        self.held.lock().unwrap().get(id).copied()
    }

    /// The lowest slot nobody holds, or None when every one is taken.
    fn free(&self) -> Option<u8> {
        let held = self.held.lock().unwrap();
        (0..SLOTS).find(|slot| !held.values().any(|(taken, _)| taken == slot))
    }

    fn hold(&self, id: &str, slot: u8, internet: bool) {
        self.held.lock().unwrap().insert(id.to_string(), (slot, internet));
    }

    fn release(&self, id: &str) -> Option<(u8, bool)> {
        self.held.lock().unwrap().remove(id)
    }
}

/// One request line: one bounded line, and nothing on it but the request itself.
fn request_line(requests: &mut BufReader<UnixStream>) -> Result<Option<String>, String> {
    match protocol::read_line(requests)? {
        Some(line) if line.trim().is_empty() => Err("an empty line is not a request".into()),
        line => Ok(line),
    }
}

fn write_reply(answers: &mut UnixStream, reply: &Reply) -> std::io::Result<()> {
    answers.write_all(format!("{}\n", reply.to_line()).as_bytes())?;
    answers.flush()
}

/// Only the helper's user may open the socket; `setup --yes` puts that user in the runner's group.
const SOCKET_MODE: u32 = 0o660;
/// The guest's first vsock id.
const FIRST_GUEST_CID: u8 = 3;
