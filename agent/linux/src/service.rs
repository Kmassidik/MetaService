//! Everything the Agent does, on top of an Engine. HTTP and the system probes live outside of it.
use crate::budget::SpaceBudget;
use crate::live_space::{Current, LiveSpace, Reading};
use crate::cpu;
use crate::engine::Engine;
use crate::gpu;
use crate::gpu_check::{self, GpuCheck};
use crate::models::*;
use crate::sandbox::Sandboxes;
use crate::ssh_install::{self, SshdFailure};
use crate::ssh_keys::{Applied, SshRequest};
use crate::validate::{BundleRequest, BundleUninstallRequest, CreateRequest};
use rand::Rng;
use std::collections::HashMap;
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

#[derive(Debug)]
pub enum Failure {
    Refused(Refusal),
    /// The request asks for something this machine does not offer, in plain words. It is answered like a bad field (400 invalid_input).
    Invalid(String),
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
    /// Workload id to the command that owns its delete. Retries join that command instead of starting another backup.
    deleting: HashMap<String, String>,
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
    /// The sandboxes this helper runs. A helper with no engine cannot run any, and says nothing about them in its facts.
    sandboxes: Arc<Sandboxes>,
}

/// The complete cause goes to the Agent's own log. Command results carry a bounded, one-line version instead.
fn log_failure(action: &str, target: &str, error: &dyn std::fmt::Debug) {
    eprintln!("{action} of {target} failed: {error:?}");
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> T {
    tokio::task::spawn_blocking(work).await.expect("a blocking task panicked")
}

impl Service {
    pub fn new(engine: Arc<dyn Engine>, budget: SpaceBudget, specs: Specs, version: &str, ledger: Arc<crate::ledger::Ledger>, installer: Arc<dyn BundleInstalling>, read_machine: impl Fn() -> Option<Reading> + Send + Sync + 'static) -> Self {
        let space = Arc::new(LiveSpace::new(budget, read_machine));
        Service {
            engine, space, specs, version: version.into(), build: None, ledger, installer, create_lock: tokio::sync::Mutex::new(()), flight: Mutex::new(Flight::default()),
            on_change: Mutex::new(None), sandboxes: Sandboxes::disabled(),
        }
    }

    /// The sandbox engine this helper runs, if any. Its records are the ones `/v1/facts` reports and the sandbox routes answer from.
    pub fn with_sandboxes(mut self, sandboxes: Arc<Sandboxes>) -> Self {
        self.sandboxes = sandboxes;
        self
    }

    pub fn sandboxes(&self) -> Arc<Sandboxes> {
        self.sandboxes.clone()
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
        let sandbox = self.sandboxes.facts();
        let space = self.fresh_space().await;
        let engine_info = EngineInfo { name: identity.name, version: identity.version, ready: problems.is_empty() };
        Ok(Facts {
            os: self.specs.os.clone(), arch: self.specs.arch.clone(), cpu_cores: self.specs.cpu_cores, cpu_model: self.specs.cpu_model.clone(), ram_total_mb: space.budget.ram_total_mb, disk_total_gb: space.budget.disk_total_gb,
            free_ram_mb: space.budget.free_ram_mb(&all), free_disk_gb: space.budget.free_disk_gb(&all), gpu: self.specs.gpu.clone(), hardware: self.specs.hardware.clone(), capabilities, problems,
            agent_version: self.version.clone(), engine: engine_info, agent_build: self.build.clone(), sandbox,
        })
    }

    pub async fn workloads(&self) -> Result<Vec<Workload>, Failure> {
        let engine = self.engine.clone();
        let mut by_id: HashMap<String, Workload> = blocking(move || engine.list()).await?.into_iter().map(|w| (w.id.clone(), w)).collect();
        let flight = self.flight.lock().unwrap();
        for (id, planned) in &flight.inflight {
            by_id.entry(id.clone()).or_insert_with(|| planned.clone());
        }
        for id in flight.deleting.keys() {
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
        let offered = blocking(move || engine.capabilities()).await;
        Capabilities { sandbox: self.sandboxes.enabled(), ..offered }
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
        if let Some(message) = cpu::not_offered(&request, &capabilities) {
            return Err(Failure::Invalid(message.into()));
        }
        space.budget.check(&request, &current, &capabilities, space.os_available_disk_gb).map_err(Failure::Refused)?;
        let id = new_workload_id();
        let planned = Workload { id: id.clone(), name: request.name.clone(), kind: request.kind, state: State::Provisioning, cpu: request.cpu, ram_mb: request.ram_mb, disk_gb: request.disk_gb, gpu_mode: request.gpu_mode, address: None, bundle_version: None, gpu_memory_gb: request.gpu_memory_gb, stopped_reason: None };
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

    /// Backs up the disk first, then deletes. A repeat for this workload joins the delete already running.
    pub async fn delete(self: &Arc<Self>, command_id: &str, id: &str) -> Result<Command, Failure> {
        if let Some(existing) = self.ledger.find(command_id) {
            return Ok(existing);
        }
        if let Some(existing) = self.deleting_command(id) {
            return Ok(existing);
        }
        self.require(id).await?;
        let was_running = self.workloads().await?.iter().any(|workload| workload.id == id && workload.state == State::Running);
        let started = Command { command_id: command_id.into(), kind: CommandType::Delete, state: CommandState::Running, workload_id: Some(id.into()), result: None };
        {
            let mut flight = self.flight.lock().unwrap();
            if let Some(owner) = flight.deleting.get(id) {
                return Ok(self.ledger.find(owner).expect("an in-flight delete has a command"));
            }
            flight.deleting.insert(id.to_string(), command_id.to_string());
            self.ledger.record(started.clone());
        }
        self.changed();
        let this = self.clone();
        let target = id.to_string();
        let echo = started.clone();
        tokio::spawn(async move { this.finish_delete(echo, target, was_running).await });
        Ok(started)
    }

    fn deleting_command(&self, id: &str) -> Option<Command> {
        let owner = self.flight.lock().unwrap().deleting.get(id).cloned();
        owner.and_then(|command_id| self.ledger.find(&command_id))
    }

    fn clear_delete(&self, id: &str, command_id: &str) {
        let mut flight = self.flight.lock().unwrap();
        if flight.deleting.get(id).map(String::as_str) != Some(command_id) {
            return;
        }
        flight.deleting.remove(id);
    }

    async fn finish_delete(self: Arc<Self>, mut command: Command, id: String, was_running: bool) {
        let engine = self.engine.clone();
        let target = id.clone();
        let stopped = if was_running {
            let engine = engine.clone();
            let target = target.clone();
            blocking(move || engine.set_running(&target, false)).await
        } else {
            Ok(())
        };
        let outcome = match stopped {
            Ok(()) => {
                let engine = engine.clone();
                let target = target.clone();
                blocking(move || engine.backup(&target).and_then(|backup| engine.delete(&target).map(|_| backup))).await
            }
            Err(error) => Err(error),
        };
        match outcome {
            Ok(backup) => finish(&mut command, true, [("backup_id", backup.as_str())]),
            Err(error) => {
                log_failure("delete", &id, &error);
                let mut reason = delete_failure(&error);
                if was_running {
                    let engine = engine.clone();
                    let target = target.clone();
                    if let Err(restart_error) = blocking(move || engine.set_running(&target, true)).await {
                        reason = format!("{reason} (could not restart: {})", delete_failure(&restart_error));
                    }
                }
                let reason = bounded_delete_failure(&reason);
                finish(&mut command, false, [("error", reason.as_str())]);
            }
        }
        self.clear_delete(&id, &command.command_id);
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

fn delete_failure(error: &EngineError) -> String {
    match error {
        EngineError::NotFound => "the machine no longer has this workload".into(),
        EngineError::Failed(reason) => bounded_delete_failure(reason),
    }
}

fn bounded_delete_failure(reason: &str) -> String {
    const MAX_BYTES: usize = 300;
    let mut one_line = reason.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut end = MAX_BYTES.min(one_line.len());
    while !one_line.is_char_boundary(end) {
        end -= 1;
    }
    one_line.truncate(end);
    if one_line.is_empty() { "the machine reported an unspecified delete failure".into() } else { one_line }
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
        service_with_engine(installer, Arc::new(SimulatedEngine::new(default_capabilities())))
    }

    fn service_with_engine(installer: Arc<Counting>, engine: Arc<SimulatedEngine>) -> Arc<Service> {
        let specs = Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, cpu_model: None, ram_total_mb: 16384, disk_total_gb: 500, gpu: Vec::new(), hardware: None };
        Arc::new(Service::new(engine, SpaceBudget::new(16384, 500), specs, "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), installer, || None))
    }

    fn workload(engine: &SimulatedEngine, id: &str) {
        let request = CreateRequest {
            command_id: "create".into(), name: id.into(), kind: Kind::Vm, cpu: 1, ram_mb: 512, disk_gb: 1, gpu_mode: GpuMode::None, image: None,
            gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None,
        };
        engine.create(id, &request).unwrap();
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
    async fn delete_announces_deleting_coalesces_retries_and_returns_the_engine_failure() {
        let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
        workload(&engine, "w-delete");
        engine.delay_backup();
        engine.fail_backup("incus export exited with 1: container is not stopped\nretry after stopping it");
        let service = service_with_engine(Arc::new(Counting::default()), engine.clone());
        let changes = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let counted = changes.clone();
        service.set_on_change(Arc::new(move || { counted.fetch_add(1, std::sync::atomic::Ordering::SeqCst); }));

        let started = service.delete("d-1", "w-delete").await.unwrap();
        assert_eq!(started.state, CommandState::Running);
        assert_eq!(changes.load(std::sync::atomic::Ordering::SeqCst), 1, "acceptance triggers an immediate heartbeat");
        let listed = service.workloads().await.unwrap();
        assert_eq!(listed.iter().find(|w| w.id == "w-delete").unwrap().state, State::Deleting);

        assert_eq!(service.delete("d-1", "w-delete").await.unwrap(), started);
        assert_eq!(service.delete("d-2", "w-delete").await.unwrap(), started, "a new command id joins the in-flight delete");
        assert!(service.command("d-2").is_none());
        assert_eq!(changes.load(std::sync::atomic::Ordering::SeqCst), 1, "a coalesced retry is not another state change");
        engine.release_backup();

        let done = finished(&service, "d-1").await;
        assert_eq!(done.state, CommandState::Failed);
        assert_eq!(done.result.unwrap()["error"], "incus export exited with 1: container is not stopped retry after stopping it");
        assert_eq!(engine.backup_calls(), 1);
        assert_eq!(engine.lifecycle_operations(), vec!["stop:w-delete", "backup:w-delete", "start:w-delete"]);
        let listed = service.workloads().await.unwrap();
        assert_eq!(listed.iter().find(|w| w.id == "w-delete").unwrap().state, State::Running);
    }

    #[tokio::test]
    async fn a_delete_step_failure_is_returned_and_leaves_the_workload_visible() {
        let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
        workload(&engine, "w-delete");
        engine.fail_delete("incus delete exited with 1: device is busy");
        let service = service_with_engine(Arc::new(Counting::default()), engine.clone());
        service.delete("d-delete", "w-delete").await.unwrap();
        let done = finished(&service, "d-delete").await;
        assert_eq!(done.state, CommandState::Failed);
        assert_eq!(done.result.unwrap()["error"], "incus delete exited with 1: device is busy");
        assert_eq!(engine.backup_calls(), 1, "the backup still happens before delete");
        assert_eq!(engine.lifecycle_operations(), vec!["stop:w-delete", "backup:w-delete", "delete:w-delete", "start:w-delete"]);
        assert_eq!(service.workloads().await.unwrap()[0].state, State::Running);
    }

    #[tokio::test]
    async fn a_restart_failure_is_reported_with_the_delete_failure() {
        let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
        workload(&engine, "w-delete");
        engine.fail_backup("export failed");
        engine.fail_restart("start failed");
        let service = service_with_engine(Arc::new(Counting::default()), engine.clone());
        service.delete("d-restart", "w-delete").await.unwrap();
        let done = finished(&service, "d-restart").await;
        assert_eq!(done.result.unwrap()["error"], "export failed (could not restart: start failed)");
        assert_eq!(service.workloads().await.unwrap()[0].state, State::Stopped);
    }

    #[test]
    fn only_the_owning_command_clears_a_delete_marker() {
        let service = service(Arc::new(Counting::default()));
        service.flight.lock().unwrap().deleting.insert("w-delete".into(), "d-owner".into());
        service.clear_delete("w-delete", "d-other");
        assert_eq!(service.flight.lock().unwrap().deleting.get("w-delete").map(String::as_str), Some("d-owner"));
        service.clear_delete("w-delete", "d-owner");
        assert!(!service.flight.lock().unwrap().deleting.contains_key("w-delete"));
    }

    #[test]
    fn delete_failure_text_is_one_bounded_utf8_line() {
        let reason = format!("  export failed\n{}", "é".repeat(200));
        let text = delete_failure(&EngineError::Failed(reason));
        assert!(text.starts_with("export failed "));
        assert_eq!(text.len(), 300);
        assert!(!text.contains('\n'));
        assert_eq!(delete_failure(&EngineError::NotFound), "the machine no longer has this workload");
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
