//! What an Agent needs from the machine's virtualization layer. One implementation per platform; the logic above it is shared.
use crate::apps::simulated::SimulatedApps;
use crate::apps::App;
use crate::ssh_install::{InstallReport, SshdFailure};
use crate::ssh_keys::{KeyList, Sshd};
use crate::models::{Capabilities, EngineError, EngineIdentity, GpuMode, Kind, Problem, State, Workload};
use crate::validate::CreateRequest;
use std::collections::HashMap;
use std::sync::Mutex;

pub trait Engine: Send + Sync {
    fn capabilities(&self) -> Capabilities;
    /// What this engine is, for the facts: a short name and its version, or None when it cannot tell. Never guessed.
    fn identity(&self) -> EngineIdentity;
    /// What on this machine stops it from running workloads right now. Empty means ready.
    fn problems(&self) -> Vec<Problem> {
        Vec::new()
    }
    fn list(&self) -> Result<Vec<Workload>, EngineError>;
    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError>;
    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError>;
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    fn backup(&self, id: &str) -> Result<String, EngineError>;
    fn delete(&self, id: &str) -> Result<(), EngineError>;
    /// Records which chat bundle version a workload has (None: none, the chat was turned off).
    fn set_bundle_version(&self, id: &str, version: Option<&str>) -> Result<(), EngineError>;
    /// Copies a file from this machine into the workload.
    fn push(&self, id: &str, host_path: &str, container_path: &str) -> Result<(), EngineError>;
    /// Runs one program inside the workload and returns what it printed. Values go in through `environment`, never into the arguments.
    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError>;
    /// Replaces the whole list of SSH public keys that may log in as root of this one workload and says whether sshd is there. The keys go in on standard input, never in arguments.
    fn apply_ssh_keys(&self, id: &str, keys: &KeyList) -> Result<Sshd, EngineError>;
    /// Installs (when missing), locks to keys only, and starts the SSH server inside the workload, with a fixed script and no request data. The keys were written before.
    fn install_sshd(&self, id: &str) -> Result<InstallReport, EngineError>;
    /// Runs the app's constant installer script inside the workload (script on standard input, no request data) and returns what it printed.
    fn install_app(&self, id: &str, app: App) -> Result<String, EngineError>;
    /// Like `exec` with no environment, for a quick look inside that must not hang: the engine gives it a short time limit.
    fn quick_exec(&self, id: &str, arguments: &[String]) -> Result<String, EngineError> {
        self.exec(id, arguments, &[])
    }
}

/// An engine that only pretends, for testing the Agent on a machine without Incus.
pub struct SimulatedEngine {
    capabilities: Capabilities,
    store: Mutex<HashMap<String, Workload>>,
    /// Per workload, the SSH key file last written, and the sshd state every apply reports (set by tests).
    ssh_keys: Mutex<HashMap<String, Vec<u8>>>,
    sshd: Mutex<Sshd>,
    /// How an install of the SSH server goes (set by tests), and how many times one was asked for.
    install: Mutex<SimulatedInstall>,
    installs: Mutex<usize>,
    /// The pretend app installs, per workload.
    pub apps: SimulatedApps,
}

/// What a simulated install of the SSH server does when the server is missing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SimulatedInstall {
    Works,
    Fails(SshdFailure),
}

pub const SIMULATED_ENGINE: &str = "simulated";

impl SimulatedEngine {
    pub fn new(capabilities: Capabilities) -> Self {
        SimulatedEngine { capabilities, store: Mutex::new(HashMap::new()), ssh_keys: Mutex::new(HashMap::new()), sshd: Mutex::new(Sshd::Missing), install: Mutex::new(SimulatedInstall::Works), installs: Mutex::new(0), apps: SimulatedApps::new() }
    }

    /// What every later apply reports about sshd, as the workload's image would decide it.
    #[cfg(test)]
    pub fn set_sshd(&self, state: Sshd) {
        *self.sshd.lock().unwrap() = state;
    }

    /// The file content last written for a workload (what went on standard input).
    #[cfg(test)]
    /// How a later install of the SSH server goes when it is missing.
    pub fn set_install(&self, mode: SimulatedInstall) {
        *self.install.lock().unwrap() = mode;
    }

    /// How many installs were asked for.
    pub fn install_calls(&self) -> usize {
        *self.installs.lock().unwrap()
    }

    pub fn written_ssh_keys(&self, id: &str) -> Option<Vec<u8>> {
        self.ssh_keys.lock().unwrap().get(id).cloned()
    }

    fn change(&self, id: &str, edit: impl FnOnce(&mut Workload)) -> Result<(), EngineError> {
        let mut store = self.store.lock().unwrap();
        edit(store.get_mut(id).ok_or(EngineError::NotFound)?);
        Ok(())
    }
}

impl Engine for SimulatedEngine {
    fn capabilities(&self) -> Capabilities {
        self.capabilities
    }

    fn identity(&self) -> EngineIdentity {
        EngineIdentity { name: SIMULATED_ENGINE.into(), version: None }
    }

    fn list(&self) -> Result<Vec<Workload>, EngineError> {
        Ok(self.store.lock().unwrap().values().cloned().collect())
    }

    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError> {
        let made = Workload {
            id: id.to_string(), name: request.name.clone(), kind: request.kind, state: State::Running, cpu: request.cpu, ram_mb: request.ram_mb,
            disk_gb: request.disk_gb, gpu_mode: request.gpu_mode, address: None, bundle_version: None, gpu_memory_gb: request.gpu_memory_gb, stopped_reason: None,
        };
        self.store.lock().unwrap().insert(id.to_string(), made.clone());
        Ok(made)
    }

    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError> {
        self.change(id, |w| w.state = if running { State::Running } else { State::Stopped })
    }

    fn backup(&self, id: &str) -> Result<String, EngineError> {
        self.change(id, |_| {})?;
        Ok(format!("backup-{id}"))
    }

    fn delete(&self, id: &str) -> Result<(), EngineError> {
        self.store.lock().unwrap().remove(id).map(|_| ()).ok_or(EngineError::NotFound)
    }

    fn set_bundle_version(&self, id: &str, version: Option<&str>) -> Result<(), EngineError> {
        self.change(id, |w| w.bundle_version = version.map(str::to_string))
    }

    fn push(&self, id: &str, _host_path: &str, _container_path: &str) -> Result<(), EngineError> {
        self.change(id, |_| {})
    }

    fn apply_ssh_keys(&self, id: &str, keys: &KeyList) -> Result<Sshd, EngineError> {
        self.change(id, |_| {})?;
        self.ssh_keys.lock().unwrap().insert(id.to_string(), keys.file_content());
        Ok(*self.sshd.lock().unwrap())
    }

    fn install_sshd(&self, id: &str) -> Result<InstallReport, EngineError> {
        self.change(id, |_| {})?;
        *self.installs.lock().unwrap() += 1;
        let mut sshd = self.sshd.lock().unwrap();
        let missing = *sshd == Sshd::Missing;
        if let (true, SimulatedInstall::Fails(failure)) = (missing, *self.install.lock().unwrap()) {
            return Ok(InstallReport { sshd: *sshd, installed: false, failure: Some(failure) });
        }
        *sshd = Sshd::Running;
        Ok(InstallReport { sshd: Sshd::Running, installed: missing, failure: None })
    }

    fn install_app(&self, id: &str, app: App) -> Result<String, EngineError> {
        self.change(id, |_| {})?;
        Ok(self.apps.run(id, app))
    }

    fn exec(&self, id: &str, _arguments: &[String], _environment: &[(String, String)]) -> Result<String, EngineError> {
        self.change(id, |_| {})?;
        Ok(String::new())
    }
}

pub fn default_capabilities() -> Capabilities {
    Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false }
}

#[allow(dead_code)]
pub fn kind_name(kind: Kind) -> &'static str {
    if kind == Kind::Vm { "vm" } else { "container" }
}

#[allow(dead_code)]
pub fn gpu_name(mode: GpuMode) -> &'static str {
    match mode {
        GpuMode::None => "none",
        GpuMode::Container => "container",
        GpuMode::Passthrough => "passthrough",
    }
}
