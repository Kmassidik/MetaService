//! The Windows engine: there is none yet. The trait is implemented so the helper's service and
//! routes work unchanged, and every VM action answers with a plain refusal that says why.
//! The capabilities say so too (`vm: false`, `container: false`), so the panel's placement refuses
//! before a create is even attempted, and the facts carry `engine: {"name":"none","ready":false}`.

use crate::engine::{AttachCommand, Engine, EngineError, EngineIdentity};
use crate::models::{Capabilities, Kind, Problem, Workload};

pub const NONE_ENGINE: &str = "none";

/// What this helper reports instead of a VM engine: the machine shares its stats, its terminal and
/// its tunnel, but it does not run workloads. Every action answers `unsupported`.
pub struct WindowsEngine;

impl Engine for WindowsEngine {
    fn capabilities(&self) -> Capabilities {
        Capabilities { vm: false, container: false, gpu_in_vm: false, gpu_in_container: false, cpu: crate::cpu::CpuOffer { qemu: None, topology: false, vendor: None }, sandbox: false }
    }

    fn identity(&self) -> EngineIdentity {
        EngineIdentity { name: NONE_ENGINE.into(), version: None }
    }

    fn problems(&self) -> Vec<Problem> {
        // The machine is healthy: no VM engine is not a problem, it is what Windows is in v1.
        Vec::new()
    }

    fn list(&self) -> Result<Vec<Workload>, EngineError> {
        Ok(Vec::new())
    }

    fn create(&self, _id: &str, _request: &crate::validate::CreateRequest) -> Result<Workload, EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn set_running(&self, _id: &str, _running: bool) -> Result<(), EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn backup(&self, _id: &str) -> Result<String, EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn delete(&self, _id: &str) -> Result<(), EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn set_bundle_version(&self, _id: &str, _version: Option<&str>) -> Result<(), EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn push(&self, _id: &str, _host_path: &str, _container_path: &str) -> Result<(), EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn exec(&self, _id: &str, _arguments: &[String], _environment: &[(String, String)]) -> Result<String, EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn apply_ssh_keys(&self, _id: &str, _keys: &crate::ssh_keys::KeyList) -> Result<crate::ssh_keys::Sshd, EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn install_sshd(&self, _id: &str) -> Result<crate::ssh_install::InstallReport, EngineError> {
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
    fn attach(&self, _id: &str) -> Result<AttachCommand, EngineError> {
        // The host terminal does not go through the engine: the route serves it directly.
        Err(EngineError::Failed(VM_MESSAGE.into()))
    }
}

/// The plain refusal for every VM action on Windows.
pub const VM_MESSAGE: &str = "Windows does not run VMs yet: this helper shares the machine's stats, terminal and tunnel only.";

#[cfg(test)]
mod tests {
    use super::*;
    use crate::validate::CreateRequest;
    use crate::models::GpuMode;
    
    fn engine() -> WindowsEngine {
        WindowsEngine
    }

    #[test]
    fn capabilities_say_no_vms_and_no_engine() {
        let caps = engine().capabilities();
        assert!(!caps.vm);
        assert!(!caps.container);
        let identity = engine().identity();
        assert_eq!(identity.name, "none");
        assert!(identity.version.is_none());
    }

    #[test]
    fn a_healthy_machine_reports_no_problems() {
        assert!(engine().problems().is_empty());
    }

    #[test]
    fn every_vm_action_refuses_with_the_plain_message() {
        let list = engine().list().unwrap();
        assert!(list.is_empty());
        let error = engine().create("w-test", &test_request()).unwrap_err();
        assert!(matches!(error, EngineError::Failed(text) if text.contains("Windows does not run VMs yet")));
        assert!(engine().set_running("w-test", true).is_err());
        assert!(engine().delete("w-test").is_err());
        assert!(engine().attach("w-test").is_err());
    }

    fn test_request() -> CreateRequest {
        CreateRequest {
            command_id: "c-test".into(),
            name: "vm".into(),
            kind: Kind::Vm,
            cpu: 1,
            ram_mb: 512,
            disk_gb: 5,
            gpu_mode: GpuMode::None,
            image: None,
            gpu_memory_gb: None,
            cpu_sockets: None,
            cpu_type: None,
            cpu_flags: Vec::new(),
            cpu_limit_percent: None,
        }
    }
}
