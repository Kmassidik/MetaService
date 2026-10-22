//! The shapes the Root sees. Field names follow contract/openapi.yaml.
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
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Gpu {
    pub vendor: String,
    pub model: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memory_mb: Option<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Capabilities {
    pub vm: bool,
    pub container: bool,
    pub gpu_in_vm: bool,
    pub gpu_in_container: bool,
}

/// What the machine is, measured once.
#[derive(Clone, Debug, PartialEq)]
pub struct Specs {
    pub os: String,
    pub arch: String,
    pub cpu_cores: u32,
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub gpu: Vec<Gpu>,
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
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub free_ram_mb: u64,
    pub free_disk_gb: u64,
    pub gpu: Vec<Gpu>,
    pub capabilities: Capabilities,
    pub problems: Vec<Problem>,
    pub agent_version: String,
    pub engine: EngineInfo,
    /// The SHA-256 of this program's file (see build.rs). Left out of the facts when it is not known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub agent_build: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CommandType {
    Create,
    Start,
    Stop,
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
