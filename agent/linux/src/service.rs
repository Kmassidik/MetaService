//! Everything the Agent does, on top of an Engine. HTTP and the system probes live outside of it.
use crate::budget::SpaceBudget;
use crate::engine::Engine;
use crate::models::*;
use crate::validate::{BundleRequest, CreateRequest};
use rand::Rng;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

pub trait BundleInstalling: Send + Sync {
    /// Puts the chat bundle on this machine or inside a workload. Blocking. The result carries the version, the port and the access key.
    fn install(&self, request: &BundleRequest) -> Result<HashMap<String, String>, String>;
    fn installed_version(&self) -> Option<String>;
}

pub enum Failure {
    Refused(Refusal),
    NotFound,
    Engine(#[allow(dead_code)] String),
}

impl From<EngineError> for Failure {
    fn from(error: EngineError) -> Self {
        match error {
            EngineError::NotFound => Failure::NotFound,
            EngineError::Failed(message) => Failure::Engine(message),
        }
    }
}

#[derive(serde::Serialize)]
pub struct Health {
    pub status: &'static str,
    pub agent_version: String,
    pub contract_version: &'static str,
    pub bundle_version: Option<String>,
}

#[derive(Default)]
struct Flight {
    inflight: HashMap<String, Workload>,
    deleting: HashSet<String>,
}

pub struct Service {
    engine: Arc<dyn Engine>,
    budget: SpaceBudget,
    specs: Specs,
    version: String,
    ledger: Arc<crate::ledger::Ledger>,
    installer: Arc<dyn BundleInstalling>,
    os_disk: fn() -> Option<u64>,
    create_lock: tokio::sync::Mutex<()>,
    flight: Mutex<Flight>,
    on_change: Mutex<Option<Arc<dyn Fn() + Send + Sync>>>,
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> T {
    tokio::task::spawn_blocking(work).await.expect("a blocking task panicked")
}

impl Service {
    pub fn new(engine: Arc<dyn Engine>, budget: SpaceBudget, specs: Specs, version: &str, ledger: Arc<crate::ledger::Ledger>, installer: Arc<dyn BundleInstalling>, os_disk: fn() -> Option<u64>) -> Self {
        Service { engine, budget, specs, version: version.into(), ledger, installer, os_disk, create_lock: tokio::sync::Mutex::new(()), flight: Mutex::new(Flight::default()), on_change: Mutex::new(None) }
    }

    /// Called when something about the workloads changed, so the Root can hear about it without waiting for the next heartbeat.
    pub fn set_on_change(&self, callback: Arc<dyn Fn() + Send + Sync>) {
        *self.on_change.lock().unwrap() = Some(callback);
    }

    fn changed(&self) {
        if let Some(callback) = self.on_change.lock().unwrap().clone() {
            callback();
        }
    }

    // ---- reading

    pub async fn health(&self) -> Health {
        let installer = self.installer.clone();
        Health { status: "ok", agent_version: self.version.clone(), contract_version: CONTRACT_VERSION, bundle_version: blocking(move || installer.installed_version()).await }
    }

    pub async fn facts(&self) -> Result<Facts, Failure> {
        let all = self.workloads().await?;
        Ok(Facts {
            os: self.specs.os.clone(), arch: self.specs.arch.clone(), cpu_cores: self.specs.cpu_cores, ram_total_mb: self.specs.ram_total_mb, disk_total_gb: self.specs.disk_total_gb,
            free_ram_mb: self.budget.free_ram_mb(&all), free_disk_gb: self.budget.free_disk_gb(&all), gpu: self.specs.gpu.clone(), capabilities: self.engine.capabilities(),
        })
    }

    pub async fn workloads(&self) -> Result<Vec<Workload>, Failure> {
        let engine = self.engine.clone();
        let mut by_id: HashMap<String, Workload> = blocking(move || engine.list()).await?.into_iter().map(|w| (w.id.clone(), w)).collect();
        let flight = self.flight.lock().unwrap();
        for (id, planned) in &flight.inflight {
            by_id.entry(id.clone()).or_insert_with(|| planned.clone());
        }
        for id in &flight.deleting {
            if let Some(found) = by_id.get_mut(id) {
                found.state = State::Deleting;
            }
        }
        let mut list: Vec<Workload> = by_id.into_values().collect();
        list.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(list)
    }

    pub fn command(&self, id: &str) -> Option<Command> {
        self.ledger.find(id)
    }

    // ---- commands

    /// Checks the space, reserves it, and creates the workload in the background. A repeat of the same command id changes nothing.
    pub async fn create(self: &Arc<Self>, request: CreateRequest) -> Result<Command, Failure> {
        let _one_at_a_time = self.create_lock.lock().await;
        if let Some(existing) = self.ledger.find(&request.command_id) {
            return Ok(existing);
        }
        let current = self.workloads().await?;
        let os_disk = self.os_disk;
        let available = blocking(os_disk).await;
        self.budget.check(&request, &current, &self.engine.capabilities(), available).map_err(Failure::Refused)?;
        let id = new_workload_id();
        let planned = Workload { id: id.clone(), name: request.name.clone(), kind: request.kind, state: State::Provisioning, cpu: request.cpu, ram_mb: request.ram_mb, disk_gb: request.disk_gb, gpu_mode: request.gpu_mode, address: None, bundle_version: None };
        self.flight.lock().unwrap().inflight.insert(id.clone(), planned);
        let started = Command { command_id: request.command_id.clone(), kind: CommandType::Create, state: CommandState::Running, workload_id: Some(id.clone()), result: None };
        self.ledger.record(started.clone());
        let this = self.clone();
        let echo = started.clone();
        tokio::spawn(async move { this.finish_create(echo, id, request).await });
        Ok(started)
    }

    async fn finish_create(self: Arc<Self>, mut command: Command, id: String, request: CreateRequest) {
        let engine = self.engine.clone();
        let made = blocking({ let id = id.clone(); move || engine.create(&id, &request) }).await;
        match made {
            Ok(_) => finish(&mut command, true, [("workload_id", id.as_str())]),
            Err(_) => finish(&mut command, false, [("error", "the machine could not create the workload")]),
        }
        self.flight.lock().unwrap().inflight.remove(&id);
        self.ledger.record(command);
        self.changed();
    }

    pub async fn set_running(&self, command_id: &str, id: &str, running: bool) -> Result<Command, Failure> {
        if let Some(existing) = self.ledger.find(command_id) {
            return Ok(existing);
        }
        self.require(id).await?;
        let kind = if running { CommandType::Start } else { CommandType::Stop };
        let mut command = Command { command_id: command_id.into(), kind, state: CommandState::Running, workload_id: Some(id.into()), result: None };
        let engine = self.engine.clone();
        let target = id.to_string();
        match blocking(move || engine.set_running(&target, running)).await {
            Ok(()) => finish(&mut command, true, [("state", if running { "running" } else { "stopped" })]),
            Err(_) => finish(&mut command, false, [("error", "the machine could not change the workload")]),
        }
        self.ledger.record(command.clone());
        self.changed();
        Ok(command)
    }

    /// Backs up the disk first, then deletes. The backup name is part of the result.
    pub async fn delete(self: &Arc<Self>, command_id: &str, id: &str) -> Result<Command, Failure> {
        if let Some(existing) = self.ledger.find(command_id) {
            return Ok(existing);
        }
        self.require(id).await?;
        self.flight.lock().unwrap().deleting.insert(id.to_string());
        let started = Command { command_id: command_id.into(), kind: CommandType::Delete, state: CommandState::Running, workload_id: Some(id.into()), result: None };
        self.ledger.record(started.clone());
        let this = self.clone();
        let target = id.to_string();
        let echo = started.clone();
        tokio::spawn(async move { this.finish_delete(echo, target).await });
        Ok(started)
    }

    async fn finish_delete(self: Arc<Self>, mut command: Command, id: String) {
        let engine = self.engine.clone();
        let target = id.clone();
        let outcome = blocking(move || engine.backup(&target).and_then(|backup| engine.delete(&target).map(|_| backup))).await;
        match outcome {
            Ok(backup) => finish(&mut command, true, [("backup_id", backup.as_str())]),
            Err(_) => finish(&mut command, false, [("error", "the machine could not delete the workload")]),
        }
        self.flight.lock().unwrap().deleting.remove(&id);
        self.ledger.record(command);
        self.changed();
    }

    /// Installs the bundle in the background. A repeat of the same command id changes nothing.
    pub async fn install_bundle(self: &Arc<Self>, request: BundleRequest) -> Result<Command, Failure> {
        if let Some(existing) = self.ledger.find(&request.command_id) {
            return Ok(existing);
        }
        if let Some(target) = &request.workload_id {
            let running = self.workloads().await?.iter().any(|w| &w.id == target && w.state == State::Running);
            if !running {
                return Err(Failure::NotFound);
            }
        }
        let started = Command { command_id: request.command_id.clone(), kind: CommandType::BundleInstall, state: CommandState::Running, workload_id: request.workload_id.clone(), result: None };
        self.ledger.record(started.clone());
        let this = self.clone();
        let echo = started.clone();
        tokio::spawn(async move { this.finish_install(echo, request).await });
        Ok(started)
    }

    async fn finish_install(self: Arc<Self>, mut command: Command, request: BundleRequest) {
        let installer = self.installer.clone();
        match blocking(move || installer.install(&request)).await {
            Ok(result) => {
                command.state = CommandState::Succeeded;
                command.result = Some(result);
            }
            Err(_) => finish(&mut command, false, [("error", "the bundle could not be installed")]),
        }
        self.ledger.record(command);
        self.changed();
    }

    async fn require(&self, id: &str) -> Result<(), Failure> {
        if self.workloads().await?.iter().any(|w| w.id == id) { Ok(()) } else { Err(Failure::NotFound) }
    }
}

fn finish<const N: usize>(command: &mut Command, ok: bool, result: [(&str, &str); N]) {
    command.state = if ok { CommandState::Succeeded } else { CommandState::Failed };
    command.result = Some(result.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect());
}

fn new_workload_id() -> String {
    const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";
    let mut random = rand::thread_rng();
    format!("w-{}", (0..8).map(|_| ALPHABET[random.gen_range(0..ALPHABET.len())] as char).collect::<String>())
}
