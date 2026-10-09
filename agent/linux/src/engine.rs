//! What an Agent needs from the machine's virtualization layer. One implementation per platform; the logic above it is shared.
use crate::models::{Capabilities, EngineError, GpuMode, Kind, State, Workload};
use crate::validate::CreateRequest;
use std::collections::HashMap;
use std::sync::Mutex;

pub trait Engine: Send + Sync {
    fn capabilities(&self) -> Capabilities;
    fn list(&self) -> Result<Vec<Workload>, EngineError>;
    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError>;
    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError>;
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    fn backup(&self, id: &str) -> Result<String, EngineError>;
    fn delete(&self, id: &str) -> Result<(), EngineError>;
    fn set_bundle_version(&self, id: &str, version: &str) -> Result<(), EngineError>;
    /// Copies a file from this machine into the workload.
    fn push(&self, id: &str, host_path: &str, container_path: &str) -> Result<(), EngineError>;
    /// Runs one program inside the workload and returns what it printed. Values go in through `environment`, never into the arguments.
    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError>;
}

/// An engine that only pretends, for testing the Agent on a machine without Incus.
pub struct SimulatedEngine {
    capabilities: Capabilities,
    store: Mutex<HashMap<String, Workload>>,
}

impl SimulatedEngine {
    pub fn new(capabilities: Capabilities) -> Self {
        SimulatedEngine { capabilities, store: Mutex::new(HashMap::new()) }
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

    fn list(&self) -> Result<Vec<Workload>, EngineError> {
        Ok(self.store.lock().unwrap().values().cloned().collect())
    }

    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError> {
        let made = Workload {
            id: id.to_string(), name: request.name.clone(), kind: request.kind, state: State::Running, cpu: request.cpu, ram_mb: request.ram_mb,
            disk_gb: request.disk_gb, gpu_mode: request.gpu_mode, address: None, bundle_version: None,
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

    fn set_bundle_version(&self, id: &str, version: &str) -> Result<(), EngineError> {
        self.change(id, |w| w.bundle_version = Some(version.to_string()))
    }

    fn push(&self, id: &str, _host_path: &str, _container_path: &str) -> Result<(), EngineError> {
        self.change(id, |_| {})
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
