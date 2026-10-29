//! The shapes the Root sees. Field names follow contract/openapi.yaml.
use crate::cpu::CpuOffer;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub const CONTRACT_VERSION: &str = "1.3.0";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Vm,
    Container,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Provisioning,
    Running,
    Stopped,
    Failed,
    Deleting,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GpuMode {
    None,
    Container,
    Passthrough,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Workload {
    pub id: String,
    pub name: String,
    pub kind: Kind,
    pub state: State,
    pub cpu: u32,
    pub ram_mb: u64,
    pub disk_gb: u64,
    pub gpu_mode: GpuMode,
    pub address: Option<String>,
    pub bundle_version: Option<String>,
    /// The GPU memory limit in GB of a container that has one, else null.
    pub gpu_memory_gb: Option<u32>,
    /// Why the helper itself stopped this workload, while it is stopped. Left out otherwise.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stopped_reason: Option<StoppedReason>,
}

pub const GPU_OVER_LIMIT_CODE: &str = "gpu_memory_over_limit";
const MIB_PER_GB: f64 = 1024.0;

/// Why a workload is stopped. The watchdog fills `code`, `message`, `used_gb` and `limit_gb`.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct StoppedReason {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub used_gb: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit_gb: Option<u32>,
}

impl StoppedReason {
    /// The reason for a stop by the GPU memory watchdog: `used_mib` is what the container's programs held, `limit_gb` its limit.
    pub fn gpu_memory_over_limit(used_mib: u64, limit_gb: u32) -> StoppedReason {
        let used_gb = (used_mib as f64 / MIB_PER_GB * 10.0).round() / 10.0;
        let message = format!("GPU memory was over its limit: used {used_gb:.1} GB, limit {limit_gb} GB.");
        StoppedReason { code: Some(GPU_OVER_LIMIT_CODE.into()), message: Some(message), used_gb: Some(used_gb), limit_gb: Some(limit_gb) }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Gpu {
    pub vendor: String,
    pub model: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memory_mb: Option<u64>,
    /// The GPU family ("Blackwell"), named from the compute capability. The five details below are left out when the driver does not say them.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub architecture: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compute_capability: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub driver_version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_clock_mhz: Option<u32>,
    /// True when the GPU has no memory of its own and works in the machine's memory (a DGX Spark).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uses_system_memory: Option<bool>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Capabilities {
    pub vm: bool,
    pub container: bool,
    pub gpu_in_vm: bool,
    pub gpu_in_container: bool,
    /// What a VM's processors can be given here: `cpu_models`, `cpu_topology` and `cpu_flags`.
    pub cpu: CpuOffer,
    /// True when this helper can run sandboxes right now. Its facts then carry `sandbox` too (see sandbox/README.md).
    pub sandbox: bool,
}

/// This helper serves the console route (`GET /v1/workloads/{id}/terminal`), so it always says `terminal: true`.
const HAS_CONSOLE: bool = true;

/// `gpu_memory_limit` is not stored: it is true exactly when `gpu_in_container` is (the watchdog needs the same NVIDIA card and toolkit).
/// `cpu_limit` is not stored either: Incus can cap the CPU time of any container (`limits.cpu.allowance`, in every version), so it follows `container`.
/// The CPU fields are always sent, like the two above; a machine that offers nothing new says `[host]`, false, `[]`.
/// `sandbox` is always sent too; a helper that cannot run sandboxes says false, and its facts carry no `sandbox` block.
impl Serialize for Capabilities {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let mut out = serializer.serialize_struct("Capabilities", 11)?;
        out.serialize_field("vm", &self.vm)?;
        out.serialize_field("container", &self.container)?;
        out.serialize_field("gpu_in_vm", &self.gpu_in_vm)?;
        out.serialize_field("gpu_in_container", &self.gpu_in_container)?;
        out.serialize_field("gpu_memory_limit", &self.gpu_in_container)?;
        out.serialize_field("terminal", &HAS_CONSOLE)?;
        out.serialize_field("cpu_models", &self.cpu.models())?;
        out.serialize_field("cpu_topology", &self.cpu.topology)?;
        out.serialize_field("cpu_flags", self.cpu.flags())?;
        out.serialize_field("cpu_limit", &self.container)?;
        out.serialize_field("sandbox", &self.sandbox)?;
        out.end()
    }
}

/// What the machine is, measured once.
#[derive(Clone, Debug, PartialEq)]
pub struct Specs {
    pub os: String,
    pub arch: String,
    pub cpu_cores: u32,
    /// The CPU name as the system reports it; None when it does not say.
    pub cpu_model: Option<String>,
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub gpu: Vec<Gpu>,
    /// What the machine is made of (see hardware.rs); None when the system says none of it.
    pub hardware: Option<crate::hardware::Hardware>,
}

/// Something on the machine that stops it from running workloads, and how to fix it. Part of the facts.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Problem {
    pub code: String,
    pub message: String,
    pub fix: String,
}

/// What an engine is: a short name and its version, or None when it cannot tell. Never guessed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EngineIdentity {
    pub name: String,
    pub version: Option<String>,
}

/// The engine as the facts report it. A missing version is sent as null.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct EngineInfo {
    pub name: String,
    pub version: Option<String>,
    pub ready: bool,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Facts {
    pub os: String,
    pub arch: String,
    pub cpu_cores: u32,
    /// The CPU name as the system reports it; left out of the facts when it does not say.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cpu_model: Option<String>,
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub free_ram_mb: u64,
    pub free_disk_gb: u64,
    pub gpu: Vec<Gpu>,
    /// What the machine is made of; left out of the facts when the system says none of it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hardware: Option<crate::hardware::Hardware>,
    pub capabilities: Capabilities,
    pub problems: Vec<Problem>,
    pub agent_version: String,
    pub engine: EngineInfo,
    /// The SHA-256 of this program's file (see build.rs). Left out of the facts when it is not known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_build: Option<String>,
    /// What this helper can offer for sandboxes, exactly when `capabilities.sandbox` is true (see sandbox/README.md).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox: Option<SandboxFacts>,
}

/// What a helper can offer for sandboxes, as `Facts.sandbox` in contract/openapi.yaml. Filled from the helper's own records, so the Root places nothing
/// here that this machine cannot take right now.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct SandboxFacts {
    pub engine: SandboxEngineInfo,
    pub max_running: u32,
    pub running: usize,
    /// How many are paused. Nothing can be paused yet, so this is 0 until pausing lands.
    pub paused: usize,
    pub max_vcpu: u32,
    pub max_ram_mb: u64,
    pub max_disk_mb: u64,
    pub booked: SandboxBooking,
    pub templates: Vec<SandboxTemplateFacts>,
    /// The number of the last sandbox event; the Root reads the events when it moves.
    pub changes: u64,
}

/// The program that runs the sandboxes here, with its version when it can tell. Never guessed.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SandboxEngineInfo {
    pub name: String,
    pub version: Option<String>,
}

/// What the sandboxes hold: vCPU and memory of the running ones, disk of every one of them.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct SandboxBooking {
    pub vcpu: u64,
    pub ram_mb: u64,
    pub disk_mb: u64,
}

/// One template built on this machine, and whether a sandbox can be made from it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SandboxTemplateFacts {
    pub id: String,
    pub build: String,
    pub ready: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CommandType {
    Create,
    Start,
    Stop,
    Restart,
    Delete,
    BundleInstall,
    BundleUninstall,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CommandState {
    Queued,
    Running,
    Succeeded,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Command {
    pub command_id: String,
    #[serde(rename = "type")]
    pub kind: CommandType,
    pub state: CommandState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workload_id: Option<String>,
    #[serde(default)]
    pub result: Option<HashMap<String, String>>,
}

/// Why a create was refused, with the numbers behind it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Refusal {
    pub code: &'static str,
    pub message: String,
    pub resource: &'static str,
    pub needed: u64,
    pub free: u64,
}

#[derive(Debug, PartialEq, Eq)]
pub enum EngineError {
    NotFound,
    Failed(String),
}

impl From<std::io::Error> for EngineError {
    fn from(error: std::io::Error) -> Self {
        EngineError::Failed(error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn the_memory_limit_capability_follows_gpu_in_container() {
        for gpu in [true, false] {
            let json = serde_json::to_value(Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: gpu, cpu: CpuOffer::HOST_ONLY, sandbox: false }).unwrap();
            assert_eq!(json["gpu_memory_limit"], gpu);
            assert_eq!(json["gpu_in_container"], gpu);
            assert_eq!(json["terminal"], true);
        }
    }

    #[test]
    fn the_cpu_capabilities_are_always_said_and_the_cap_follows_container() {
        let plain = serde_json::to_value(Capabilities { vm: true, container: false, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY, sandbox: false }).unwrap();
        assert_eq!((&plain["cpu_models"], &plain["cpu_topology"], &plain["cpu_flags"], &plain["cpu_limit"]), (&json!(["host"]), &json!(false), &json!([]), &json!(false)));
        let offer = CpuOffer::new("x86_64", Some((8, 0)), true, Some(crate::cpu::CpuVendor::Intel));
        let json = serde_json::to_value(Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: offer, sandbox: true }).unwrap();
        assert_eq!(json["cpu_models"][0], "host");
        assert!(json["cpu_models"].as_array().unwrap().contains(&json!("SapphireRapids")) && !json["cpu_models"].as_array().unwrap().contains(&json!("EPYC-Genoa")));
        assert_eq!((&json["cpu_topology"], &json["cpu_flags"], &json["cpu_limit"]), (&json!(true), &json!(["nested-virt", "aes"]), &json!(true)));
        assert_eq!((json["sandbox"].clone(), json.as_object().unwrap().len()), (json!(true), 11), "a helper that can run sandboxes says so");
    }

    #[test]
    fn the_over_limit_reason_has_one_decimal() {
        let reason = StoppedReason::gpu_memory_over_limit(5325, 4);
        assert_eq!(reason.message.as_deref(), Some("GPU memory was over its limit: used 5.2 GB, limit 4 GB."));
        assert_eq!((reason.used_gb, reason.limit_gb), (Some(5.2), Some(4)));
        let json = serde_json::to_value(&reason).unwrap();
        assert_eq!(json["code"], "gpu_memory_over_limit");
    }
}
