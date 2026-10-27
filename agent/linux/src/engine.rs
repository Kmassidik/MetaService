//! What an Agent needs from the machine's virtualization layer. One implementation per platform; the logic above it is shared.
use crate::apps::simulated::SimulatedApps;
use crate::apps::App;
use crate::cpu::CpuOffer;
use crate::ssh_install::{InstallReport, SshdFailure};
use crate::ssh_keys::{KeyList, Sshd};
use crate::models::{Capabilities, EngineError, EngineIdentity, GpuMode, Kind, Problem, State, Workload};
use crate::validate::CreateRequest;
use std::collections::HashMap;
use std::sync::Mutex;

/// The program that gives a person a shell inside a workload, as a program path and its arguments. It never goes through a shell of ours.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AttachCommand {
    pub program: String,
    pub arguments: Vec<String>,
}

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
    /// What to run on a pty to get an interactive shell inside the workload. The workload must exist; a VM must also answer inside (it has the guest agent),
    /// else this is an error that says so. The command comes only from the engine and the helper's own id, never from a caller.
    fn attach(&self, id: &str) -> Result<AttachCommand, EngineError>;
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
    /// What a console runs on the host instead of a real workload's shell (tests change it).
    attach: Mutex<AttachCommand>,
    #[cfg(test)]
    backup_failure: Mutex<Option<String>>,
    #[cfg(test)]
    delete_failure: Mutex<Option<String>>,
    #[cfg(test)]
    backup_delay: Mutex<Option<std::sync::Arc<(Mutex<bool>, std::sync::Condvar)>>>,
    #[cfg(test)]
    backup_calls: Mutex<usize>,
    #[cfg(test)]
    restart_failure: Mutex<Option<String>>,
    #[cfg(test)]
    lifecycle_operations: Mutex<Vec<String>>,
}

/// What a simulated install of the SSH server does when the server is missing.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SimulatedInstall {
    Works,
    Fails(SshdFailure),
}

pub const SIMULATED_ENGINE: &str = "simulated";
/// The simulated engine has no workloads to enter, so a console runs this program on the host.
const SIMULATED_SHELL: &str = "/bin/sh";

impl SimulatedEngine {
    pub fn new(capabilities: Capabilities) -> Self {
        SimulatedEngine {
            capabilities, store: Mutex::new(HashMap::new()), ssh_keys: Mutex::new(HashMap::new()), sshd: Mutex::new(Sshd::Missing), install: Mutex::new(SimulatedInstall::Works), installs: Mutex::new(0), apps: SimulatedApps::new(), attach: Mutex::new(AttachCommand { program: SIMULATED_SHELL.into(), arguments: vec![] }),
            #[cfg(test)] backup_failure: Mutex::new(None),
            #[cfg(test)] delete_failure: Mutex::new(None),
            #[cfg(test)] backup_delay: Mutex::new(None),
            #[cfg(test)] backup_calls: Mutex::new(0),
            #[cfg(test)] restart_failure: Mutex::new(None),
            #[cfg(test)] lifecycle_operations: Mutex::new(Vec::new()),
        }
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

    /// What every later console runs.
    #[cfg(test)]
    pub fn set_attach(&self, program: &str, arguments: &[&str]) {
        *self.attach.lock().unwrap() = AttachCommand { program: program.into(), arguments: arguments.iter().map(|a| a.to_string()).collect() };
    }

    pub fn written_ssh_keys(&self, id: &str) -> Option<Vec<u8>> {
        self.ssh_keys.lock().unwrap().get(id).cloned()
    }

    #[cfg(test)]
    pub fn fail_backup(&self, reason: &str) {
        *self.backup_failure.lock().unwrap() = Some(reason.into());
    }

    #[cfg(test)]
    pub fn fail_delete(&self, reason: &str) {
        *self.delete_failure.lock().unwrap() = Some(reason.into());
    }

    #[cfg(test)]
    pub fn delay_backup(&self) {
        *self.backup_delay.lock().unwrap() = Some(std::sync::Arc::new((Mutex::new(false), std::sync::Condvar::new())));
    }

    #[cfg(test)]
    pub fn release_backup(&self) {
        let delay = self.backup_delay.lock().unwrap().clone();
        if let Some(delay) = delay {
            let (released, wake) = &*delay;
            *released.lock().unwrap() = true;
            wake.notify_all();
        }
    }

    #[cfg(test)]
    pub fn backup_calls(&self) -> usize {
        *self.backup_calls.lock().unwrap()
    }

    #[cfg(test)]
    pub fn fail_restart(&self, reason: &str) {
        *self.restart_failure.lock().unwrap() = Some(reason.into());
    }

    #[cfg(test)]
    pub fn lifecycle_operations(&self) -> Vec<String> {
        self.lifecycle_operations.lock().unwrap().clone()
    }

    #[cfg(test)]
    fn record_lifecycle(&self, operation: String) {
        self.lifecycle_operations.lock().unwrap().push(operation);
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
        #[cfg(test)]
        {
            self.record_lifecycle(format!("{}:{id}", if running { "start" } else { "stop" }));
            if running {
                if let Some(reason) = self.restart_failure.lock().unwrap().clone() {
                    return Err(EngineError::Failed(reason));
                }
            }
        }
        self.change(id, |w| w.state = if running { State::Running } else { State::Stopped })
    }

    fn backup(&self, id: &str) -> Result<String, EngineError> {
        #[cfg(test)]
        {
            self.record_lifecycle(format!("backup:{id}"));
            *self.backup_calls.lock().unwrap() += 1;
            let delay = self.backup_delay.lock().unwrap().clone();
            if let Some(delay) = delay {
                let (released, wake) = &*delay;
                let mut released = released.lock().unwrap();
                while !*released {
                    released = wake.wait(released).unwrap();
                }
            }
            let failure = self.backup_failure.lock().unwrap().clone();
            if let Some(reason) = failure {
                return Err(EngineError::Failed(reason));
            }
        }
        self.change(id, |_| {})?;
        Ok(format!("backup-{id}"))
    }

    fn delete(&self, id: &str) -> Result<(), EngineError> {
        #[cfg(test)]
        self.record_lifecycle(format!("delete:{id}"));
        #[cfg(test)]
        if let Some(reason) = self.delete_failure.lock().unwrap().clone() {
            return Err(EngineError::Failed(reason));
        }
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

    fn attach(&self, id: &str) -> Result<AttachCommand, EngineError> {
        self.change(id, |_| {})?;
        Ok(self.attach.lock().unwrap().clone())
    }

    fn exec(&self, id: &str, _arguments: &[String], _environment: &[(String, String)]) -> Result<String, EngineError> {
        self.change(id, |_| {})?;
        Ok(String::new())
    }
}

pub fn default_capabilities() -> Capabilities {
    Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY, sandbox: false }
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
