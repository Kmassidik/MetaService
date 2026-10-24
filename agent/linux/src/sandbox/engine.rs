//! What the helper needs from the program that makes sandboxes, and the one engine it has now: a simulated one that needs no root and no Firecracker.
//!
//! The real engine (Firecracker + jailer, a network namespace per sandbox, the daemon inside, snapshots) comes in a later slice. Everything above this
//! trait — the records, the end times, the events, the routes — is written so it only has to be given another engine.
use super::record::Sandbox;
use crate::budget::SpaceBudget;
use crate::models::Specs;
use std::collections::HashSet;
use std::sync::Mutex;

/// The template every machine has: Ubuntu 24.04 with the in-guest daemon and a user named `user` (sandbox/README.md).
pub const BASE_TEMPLATE: &str = "base";
/// How many sandboxes may run on one machine at once, until the machine's owner sets another.
pub const MAX_RUNNING: u32 = 32;
/// A sandbox may take this share of what the machine is allowed to hand out.
const SHARE_OF_MACHINE: u64 = 4;
const MB_PER_GB: u64 = 1024;
const BASE_BUILD: &str = "1";
const BASE_SIZE_MB: u64 = 1024;
const NO_MESSAGE: Option<String> = None;

/// What one sandbox may take here, and how many may run at once. The facts say the same numbers, so the Root can refuse before it asks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Limits {
    pub max_running: u32,
    pub max_vcpu: u32,
    pub max_ram_mb: u64,
    pub max_disk_mb: u64,
}

impl Limits {
    /// A machine's own limits: its cores for one sandbox at most, and a share of what it may hand out for one sandbox's memory and disk.
    pub fn of(specs: &Specs, budget: &SpaceBudget) -> Limits {
        let ram_mb = budget.ram_allowance_mb.unwrap_or(budget.ram_total_mb) / SHARE_OF_MACHINE;
        let disk_gb = budget.disk_allowance_gb.unwrap_or(budget.disk_total_gb);
        Limits {
            max_running: MAX_RUNNING,
            max_vcpu: specs.cpu_cores.max(1),
            max_ram_mb: ram_mb.max(super::record::MIN_RAM_MB),
            max_disk_mb: (disk_gb * MB_PER_GB / SHARE_OF_MACHINE).max(super::record::MIN_DISK_MB),
        }
    }
}

/// A template as this machine has it. `state` is the contract's own word: `ready`, `building` or `failed`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Template {
    pub id: String,
    pub build: String,
    pub state: &'static str,
    /// Seconds since 1970, UTC; None while it is still building.
    pub built_at: Option<u64>,
    pub size_mb: u64,
    pub message: Option<String>,
}

impl Template {
    pub fn ready(&self) -> bool {
        self.state == super::record::TEMPLATE_READY
    }
}

/// One reading of a sandbox's CPU, memory and disk, as `/v1/sandboxes/{id}/metrics` answers them.
#[derive(Clone, Debug, PartialEq)]
pub struct Sample {
    /// Seconds since 1970, UTC.
    pub at: u64,
    pub cpu_count: u32,
    pub cpu_used_pct: f64,
    pub mem_used_mb: u64,
    pub mem_total_mb: u64,
    pub disk_used_mb: u64,
    pub disk_total_mb: u64,
}

impl serde::Serialize for Sample {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let mut out = serializer.serialize_struct("Sample", 7)?;
        out.serialize_field("at", &super::time::iso8601(self.at))?;
        out.serialize_field("cpu_count", &self.cpu_count)?;
        out.serialize_field("cpu_used_pct", &self.cpu_used_pct)?;
        out.serialize_field("mem_used_mb", &self.mem_used_mb)?;
        out.serialize_field("mem_total_mb", &self.mem_total_mb)?;
        out.serialize_field("disk_used_mb", &self.disk_used_mb)?;
        out.serialize_field("disk_total_mb", &self.disk_total_mb)?;
        out.end()
    }
}

pub trait SandboxEngine: Send + Sync {
    /// The engine's short name for the facts: `firecracker` (or `simulated` for the test engine), and its version when it can tell. Never guessed.
    fn name(&self) -> &'static str;
    fn version(&self) -> Option<String> {
        None
    }
    fn limits(&self) -> Limits;
    fn templates(&self) -> Vec<Template>;
    /// Starts it and answers once it is ready. The Err is the engine's own plain reason, for the helper's log: what the helper tried lives here, not in
    /// the engine, so the traits says nothing about the contract's codes.
    fn create(&self, sandbox: &Sandbox) -> Result<(), String>;
    /// Stops a sandbox that is still there, and says nothing when it is gone already: the helper's own record is what the Root reads.
    fn stop(&self, id: &str) -> Result<(), String>;
    /// Removes everything the sandbox had.
    fn delete(&self, id: &str) -> Result<(), String>;
    fn metrics(&self, sandbox: &Sandbox, now: u64) -> Vec<Sample>;
}

/// An engine that only pretends: it keeps the ids of the sandboxes it would run and needs no root, no KVM and no Firecracker.
/// It is what the contract tests run on; it makes no microVM, so nothing inside one of its sandboxes can be reached.
pub struct SimulatedSandboxEngine {
    limits: Limits,
    /// The templates it pretends to have built, and the ids of the sandboxes it pretends to run.
    templates: Vec<Template>,
    running: Mutex<HashSet<String>>,
}

pub const SIMULATED: &str = "simulated";

impl SimulatedSandboxEngine {
    pub fn new(limits: Limits) -> Self {
        let template = Template { id: BASE_TEMPLATE.into(), build: BASE_BUILD.into(), state: super::record::TEMPLATE_READY, built_at: Some(super::time::now()), size_mb: BASE_SIZE_MB, message: NO_MESSAGE };
        SimulatedSandboxEngine { limits, templates: vec![template], running: Mutex::new(HashSet::new()) }
    }

    /// The ids it pretends to run, for the tests to look at.
    #[cfg(test)]
    pub fn running(&self) -> Vec<String> {
        let mut ids: Vec<String> = self.running.lock().unwrap().iter().cloned().collect();
        ids.sort();
        ids
    }
}

impl SandboxEngine for SimulatedSandboxEngine {
    fn name(&self) -> &'static str {
        SIMULATED
    }

    fn limits(&self) -> Limits {
        self.limits
    }

    fn templates(&self) -> Vec<Template> {
        self.templates.clone()
    }

    fn create(&self, sandbox: &Sandbox) -> Result<(), String> {
        self.running.lock().unwrap().insert(sandbox.id.clone());
        Ok(())
    }

    fn stop(&self, id: &str) -> Result<(), String> {
        self.forget(id)
    }

    fn delete(&self, id: &str) -> Result<(), String> {
        self.forget(id)
    }

    fn metrics(&self, sandbox: &Sandbox, now: u64) -> Vec<Sample> {
        vec![Sample { at: now, cpu_count: sandbox.vcpu, cpu_used_pct: 0.0, mem_used_mb: 0, mem_total_mb: sandbox.ram_mb, disk_used_mb: 0, disk_total_mb: sandbox.disk_mb }]
    }
}

impl SimulatedSandboxEngine {
    /// A sandbox that is not there any more is not an error: the helper's own record decides what the Root is told.
    fn forget(&self, id: &str) -> Result<(), String> {
        self.running.lock().unwrap().remove(id);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn specs(cores: u32) -> Specs {
        Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: cores, cpu_model: None, ram_total_mb: 65536, disk_total_gb: 2000, gpu: Vec::new() }
    }

    #[test]
    fn the_limits_of_a_machine_are_a_share_of_it_and_never_below_one_sandbox() {
        let limits = Limits::of(&specs(16), &SpaceBudget::new(65536, 2000));
        assert_eq!((limits.max_running, limits.max_vcpu), (MAX_RUNNING, 16));
        assert_eq!((limits.max_ram_mb, limits.max_disk_mb), (65536 / SHARE_OF_MACHINE, 2000 * MB_PER_GB / SHARE_OF_MACHINE));
        let tiny = Limits::of(&specs(1), &SpaceBudget::new(512, 1));
        assert_eq!((tiny.max_ram_mb, tiny.max_disk_mb), (super::super::record::MIN_RAM_MB, super::super::record::MIN_DISK_MB), "a small machine still takes a small sandbox");
    }

    #[test]
    fn the_simulated_engine_has_the_base_template_and_keeps_the_ids_it_would_run() {
        let engine = SimulatedSandboxEngine::new(Limits { max_running: 4, max_vcpu: 8, max_ram_mb: 4096, max_disk_mb: 8192 });
        assert_eq!(engine.templates().iter().map(|t| (t.id.as_str(), t.ready())).collect::<Vec<_>>(), [(BASE_TEMPLATE, true)]);
        assert_eq!((engine.name(), engine.version()), (SIMULATED, None));
        assert_eq!(engine.limits().max_vcpu, 8);
        assert!(engine.stop("never-made").is_ok(), "stopping what is not there is not a failure");
    }
}
