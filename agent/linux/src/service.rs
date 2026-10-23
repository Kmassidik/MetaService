//! Everything the Agent does, on top of an Engine. HTTP and the system probes live outside of it.
use crate::budget::SpaceBudget;
use crate::live_space::{Current, LiveSpace, Reading};
use crate::engine::Engine;
use crate::gpu;
use crate::gpu_check::{self, GpuCheck};
use crate::models::*;
use crate::ssh_install::{self, SshdFailure};
use crate::ssh_keys::{Applied, SshRequest};
use crate::validate::{BundleRequest, BundleUninstallRequest, CreateRequest};
use rand::Rng;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

/// What a turned-off chat leaves behind, named in the command result.
const KEPT_CHAT_DATA: &str = "chat-data";

pub trait BundleInstalling: Send + Sync {
    /// Puts the chat bundle on this machine or inside a workload. Blocking. The result carries the version, the port and the access key.
    fn install(&self, request: &BundleRequest) -> Result<HashMap<String, String>, String>;
    /// Turns the chat off on this machine or in a workload. It stops; the folder with its conversations stays. Blocking.
    fn uninstall(&self, workload_id: Option<&str>) -> Result<(), String>;
    fn installed_version(&self) -> Option<String>;
}

pub enum Failure {
    Refused(Refusal),
    NotFound,
    Engine(#[allow(dead_code)] String),
    /// The SSH server could not be made to listen inside the VM (the keys were still written).
    Sshd(SshdFailure),
    /// An app could not be put in the VM (plain words and the installer's last lines).
    App(crate::apps::AppError),
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
    pub(crate) engine: Arc<dyn Engine>,
    space: Arc<LiveSpace>,
    specs: Specs,
    version: String,
    build: Option<String>,
    ledger: Arc<crate::ledger::Ledger>,
    installer: Arc<dyn BundleInstalling>,
    create_lock: tokio::sync::Mutex<()>,
    flight: Mutex<Flight>,
    on_change: Mutex<Option<Arc<dyn Fn() + Send + Sync>>>,
}

/// The cause of a failed action goes to the Agent's own log and never to the Root, because it can name paths and program output.
fn log_failure(action: &str, target: &str, error: &dyn std::fmt::Debug) {
    eprintln!("{action} of {target} failed: {error:?}");
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> T {
    tokio::task::spawn_blocking(work).await.expect("a blocking task panicked")
}

impl Service {
    pub fn new(engine: Arc<dyn Engine>, budget: SpaceBudget, specs: Specs, version: &str, ledger: Arc<crate::ledger::Ledger>, installer: Arc<dyn BundleInstalling>, read_machine: impl Fn() -> Option<Reading> + Send + Sync + 'static) -> Self {
        let space = Arc::new(LiveSpace::new(budget, read_machine));
        Service { engine, space, specs, version: version.into(), build: None, ledger, installer, create_lock: tokio::sync::Mutex::new(()), flight: Mutex::new(Flight::default()), on_change: Mutex::new(None) }
    }

    /// Says which build of the program this is (see build.rs); it goes into the facts.
    pub fn with_build(mut self, build: Option<String>) -> Self {
        self.build = build;
        self
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

    /// Re-reads the machine's totals; used before every space decision and every facts report.
    async fn fresh_space(&self) -> Current {
        let space = self.space.clone();
        blocking(move || space.refresh()).await
    }

    // ---- reading

    pub async fn health(&self) -> Health {
        let installer = self.installer.clone();
        Health { status: "ok", agent_version: self.version.clone(), contract_version: CONTRACT_VERSION, bundle_version: blocking(move || installer.installed_version()).await }
    }

    pub async fn facts(&self) -> Result<Facts, Failure> {
        let all = self.workloads().await?;
        let engine = self.engine.clone();
        let for_problems = engine.clone();
        let problems = blocking(move || for_problems.problems()).await;
        let identity = blocking(move || engine.identity()).await;
        let capabilities = self.capabilities().await;
        let space = self.fresh_space().await;
        let engine_info = EngineInfo { name: identity.name, version: identity.version, ready: problems.is_empty() };
        Ok(Facts {
            os: self.specs.os.clone(), arch: self.specs.arch.clone(), cpu_cores: self.specs.cpu_cores, ram_total_mb: space.budget.ram_total_mb, disk_total_gb: space.budget.disk_total_gb,
            free_ram_mb: space.budget.free_ram_mb(&all), free_disk_gb: space.budget.free_disk_gb(&all), gpu: self.specs.gpu.clone(), capabilities, problems,
            agent_version: self.version.clone(), engine: engine_info, agent_build: self.build.clone(),
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

    /// What the engine can do right now. It looks at the host (for the GPU toolkit), so it runs off the async threads.
    async fn capabilities(&self) -> Capabilities {
        let engine = self.engine.clone();
        blocking(move || engine.capabilities()).await
    }

    /// Looks inside a running container for the GPU. A VM, or a container that was not given the GPU, is answered without running anything inside it.
    pub async fn gpu_check(&self, id: &str) -> Result<GpuCheck, Failure> {
        let found = self.workloads().await?.into_iter().find(|w| w.id == id).ok_or(Failure::NotFound)?;
        if found.kind != Kind::Container || found.gpu_mode != GpuMode::Container {
            return Ok(gpu_check::not_given());
        }
        if found.state != State::Running {
            return Err(Failure::Refused(Refusal { code: "not_running", message: "start it first: the GPU can only be checked inside a running container".into(), resource: "state", needed: 1, free: 0 }));
        }
        let engine = self.engine.clone();
        let target = id.to_string();
        let look = move || gpu_check::look(&|call| engine.quick_exec(&target, &call.iter().map(|part| part.to_string()).collect::<Vec<_>>()));
        Ok(blocking(look).await)
    }

    /// Sets the complete list of SSH keys for root of one workload and reports sshd. The workload must exist (404) and be running (409 `not_running`).
    pub async fn apply_ssh_keys(&self, id: &str, request: SshRequest) -> Result<Applied, Failure> {
        let found = self.workloads().await?.into_iter().find(|w| w.id == id).ok_or(Failure::NotFound)?;
        if found.state != State::Running {
            return Err(Failure::Refused(Refusal { code: "not_running", message: "start it first: SSH keys can only be set inside a running workload".into(), resource: "state", needed: 1, free: 0 }));
        }
        let engine = self.engine.clone();
        let target = id.to_string();
        blocking(move || ssh_install::apply(engine.as_ref(), &target, &request)).await
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
        let space = self.fresh_space().await;
        let capabilities = self.capabilities().await;
        if let Some(refused) = gpu::refusal(&request, !self.specs.gpu.is_empty(), &capabilities) {
            return Err(Failure::Refused(refused));
        }
        space.budget.check(&request, &current, &capabilities, space.os_available_disk_gb).map_err(Failure::Refused)?;
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
            Err(error) => {
                log_failure("create", &id, &error);
                finish(&mut command, false, [("error", "the machine could not create the workload")]);
            }
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
            Err(error) => {
                log_failure("start or stop", id, &error);
                finish(&mut command, false, [("error", "the machine could not change the workload")]);
            }
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
            Err(error) => {
                log_failure("delete", &id, &error);
                finish(&mut command, false, [("error", "the machine could not delete the workload")]);
            }
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
            Err(error) => {
                log_failure("bundle install", command.workload_id.as_deref().unwrap_or("machine"), &error);
                finish(&mut command, false, [("error", "the bundle could not be installed")]);
            }
        }
        self.ledger.record(command);
        self.changed();
    }

    /// Turns the chat off in the background. A repeat of the same command id changes nothing.
    pub async fn uninstall_bundle(self: &Arc<Self>, request: BundleUninstallRequest) -> Result<Command, Failure> {
        if let Some(existing) = self.ledger.find(&request.command_id) {
            return Ok(existing);
        }
        if let Some(target) = &request.workload_id {
            let running = self.workloads().await?.iter().any(|w| &w.id == target && w.state == State::Running);
            if !running {
                return Err(Failure::NotFound);
            }
        }
        let started = Command { command_id: request.command_id.clone(), kind: CommandType::BundleUninstall, state: CommandState::Running, workload_id: request.workload_id.clone(), result: None };
        self.ledger.record(started.clone());
        let this = self.clone();
        let echo = started.clone();
        tokio::spawn(async move { this.finish_uninstall(echo, request).await });
        Ok(started)
    }

    async fn finish_uninstall(self: Arc<Self>, mut command: Command, request: BundleUninstallRequest) {
        let installer = self.installer.clone();
        let target = request.workload_id.clone();
        match blocking(move || installer.uninstall(target.as_deref())).await {
            Ok(()) => finish(&mut command, true, [("kept", KEPT_CHAT_DATA)]),
            Err(error) => {
                log_failure("bundle uninstall", command.workload_id.as_deref().unwrap_or("machine"), &error);
                finish(&mut command, false, [("error", "the chat could not be turned off")]);
            }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::{default_capabilities, SimulatedEngine};

    /// An installer that only counts, so the service's own part can be looked at.
    #[derive(Default)]
    struct Counting {
        uninstalled: Mutex<Vec<Option<String>>>,
        fail: bool,
    }

    impl BundleInstalling for Counting {
        fn install(&self, _request: &BundleRequest) -> Result<HashMap<String, String>, String> {
            Ok(HashMap::new())
        }

        fn uninstall(&self, workload_id: Option<&str>) -> Result<(), String> {
            if self.fail {
                return Err("secret path /Users/x leaked".into());
            }
            self.uninstalled.lock().unwrap().push(workload_id.map(str::to_string));
            Ok(())
        }

        fn installed_version(&self) -> Option<String> {
            None
        }
    }

    fn service(installer: Arc<Counting>) -> Arc<Service> {
        let specs = Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, ram_total_mb: 16384, disk_total_gb: 500, gpu: Vec::new() };
        let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
        Arc::new(Service::new(engine, SpaceBudget::new(16384, 500), specs, "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), installer, || None))
    }

    async fn finished(service: &Arc<Service>, id: &str) -> Command {
        for _ in 0..200 {
            if let Some(found) = service.command(id).filter(|c| c.state != CommandState::Running) {
                return found;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        panic!("the command did not finish");
    }

    #[tokio::test]
    async fn the_facts_name_the_helper_and_the_engine_and_say_it_is_ready() {
        let service = service(Arc::new(Counting::default()));
        let facts = service.facts().await.ok().unwrap();
        assert_eq!(facts.agent_version, "0.9.9");
        assert_eq!(facts.agent_version, service.health().await.agent_version);
        assert_eq!(facts.engine, EngineInfo { name: "simulated".into(), version: None, ready: true });
        let json = serde_json::to_value(&facts).unwrap();
        assert!(json["engine"]["version"].is_null(), "an unknown version is sent as null");
    }

    #[tokio::test]
    async fn the_facts_carry_the_build_only_when_there_is_one() {
        let silent = service(Arc::new(Counting::default()));
        let json = serde_json::to_value(silent.facts().await.ok().unwrap()).unwrap();
        assert!(json.get("agent_build").is_none(), "a helper that does not know its build says nothing");
        let build = "ab".repeat(32);
        let known = Arc::try_unwrap(service(Arc::new(Counting::default()))).ok().unwrap().with_build(Some(build.clone()));
        let json = serde_json::to_value(known.facts().await.ok().unwrap()).unwrap();
        assert_eq!(json["agent_build"], build);
    }

    #[tokio::test]
    async fn turning_the_chat_off_runs_on_the_installer_and_a_repeat_runs_once() {
        let installer = Arc::new(Counting::default());
        let service = service(installer.clone());
        let request = BundleUninstallRequest { command_id: "u-1".into(), workload_id: None };
        let started = service.uninstall_bundle(request.clone()).await.ok().unwrap();
        assert_eq!(started.kind, CommandType::BundleUninstall);
        assert_eq!(finished(&service, "u-1").await.state, CommandState::Succeeded);
        service.uninstall_bundle(request).await.ok().unwrap();
        assert_eq!(*installer.uninstalled.lock().unwrap(), vec![None]);
    }

    #[tokio::test]
    async fn turning_the_chat_off_in_a_workload_that_is_not_there_is_not_found() {
        let service = service(Arc::new(Counting::default()));
        let result = service.uninstall_bundle(BundleUninstallRequest { command_id: "u-2".into(), workload_id: Some("w-none".into()) }).await;
        assert!(matches!(result, Err(Failure::NotFound)));
    }

    #[tokio::test]
    async fn a_failed_uninstall_says_nothing_about_the_inside() {
        let service = service(Arc::new(Counting { fail: true, ..Counting::default() }));
        service.uninstall_bundle(BundleUninstallRequest { command_id: "u-3".into(), workload_id: None }).await.ok().unwrap();
        let done = finished(&service, "u-3").await;
        assert_eq!(done.state, CommandState::Failed);
        assert_eq!(done.result.unwrap()["error"], "the chat could not be turned off");
    }
}
