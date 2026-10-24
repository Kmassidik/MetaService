//! Workloads as Incus instances: VMs and containers, one engine. Every call is the `incus` program with a fixed argument list;
//! nothing a user typed can become a flag, because names and ids are checked against the id pattern and the image against the image pattern first.
mod attach;
mod list;
mod runner;
mod server;

use crate::apps::{self, App};
use crate::cpu::{CpuOffer, CpuVendor};
use crate::engine::{AttachCommand, Engine};
use crate::gpu;
use crate::models::{Capabilities, EngineError, EngineIdentity, Kind, Problem, State, Workload};
use crate::preflight::{self, HostProbe, NoHostChecks};
use crate::ssh_install::{self, InstallReport};
use crate::ssh_keys::{self, KeyList, Sshd};
use crate::validate::CreateRequest;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub use list::{cpu_model_arguments, gpu_device_arguments, init_arguments, launch_arguments, parse_list, start_arguments, GPU_STOP_CODE_KEY, GPU_STOP_USED_KEY};
pub use attach::NO_AGENT_MESSAGE;
pub use runner::{ProcessRunner, Runner};
use server::ServerCpu;

const PREFIX: &str = "ms-";
pub const ENGINE_NAME: &str = "incus";
const BUNDLE_VERSION_KEY: &str = "user.metaservice.bundle_version";
const STOP_SECONDS: &str = "30";
const QUICK: Duration = Duration::from_secs(30);
const SLOW: Duration = Duration::from_secs(900);
/// The most an install of the SSH server inside a VM may take (it downloads a package).
const INSTALL_TIMEOUT: Duration = Duration::from_secs(300);

pub struct IncusEngine {
    runner: Arc<dyn Runner>,
    capabilities: Capabilities,
    backup_dir: PathBuf,
    default_image: String,
    wait_seconds: u64,
    probe: Arc<dyn HostProbe>,
    /// An NVIDIA card was found. Containers can use it only while the container toolkit is also there, which is looked at each time.
    gpu_found: bool,
    /// Asked for once the program answers, then remembered.
    version: Mutex<Option<String>>,
    /// Who made this machine's CPU, read once at start. It decides what nested-virt is.
    cpu_vendor: Option<CpuVendor>,
    /// What the server says about VMs' processors (the QEMU version, sockets): asked for once it answers, then remembered.
    server: Mutex<Option<ServerCpu>>,
}

/// The Incus instance name of a workload id.
pub fn name_of(id: &str) -> String {
    format!("{PREFIX}{id}")
}

fn args(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

impl IncusEngine {
    pub fn new(runner: Arc<dyn Runner>, capabilities: Capabilities, backup_dir: PathBuf, default_image: String, wait_seconds: u64) -> Self {
        IncusEngine { runner, capabilities, backup_dir, default_image, wait_seconds, probe: Arc::new(NoHostChecks), gpu_found: false, version: Mutex::new(None), cpu_vendor: None, server: Mutex::new(None) }
    }

    /// Lets the engine look at the host (the firewall) when it reports problems.
    pub fn with_probe(mut self, probe: Arc<dyn HostProbe>) -> Self {
        self.probe = probe;
        self
    }

    /// Says an NVIDIA card is in this machine, so `gpu_in_container` follows whether the container toolkit is installed.
    pub fn with_gpu_found(mut self, found: bool) -> Self {
        self.gpu_found = found;
        self
    }

    /// Says who made this machine's CPU, so VMs can have nested-virt and aes switched on or off.
    pub fn with_cpu_vendor(mut self, vendor: Option<CpuVendor>) -> Self {
        self.cpu_vendor = vendor;
        self
    }

    /// What a VM's processors can be given here. A server that cannot answer yet offers nothing that needs its word (models beyond host, sockets);
    /// it is asked again next time, and the heartbeat goes on either way.
    fn cpu_offer(&self) -> CpuOffer {
        let mut known = self.server.lock().unwrap();
        if known.is_none() {
            *known = self.runner.run(&server::query_arguments(), QUICK).ok().and_then(|text| server::parse_server(&text));
        }
        let server = known.unwrap_or_default();
        CpuOffer::new(std::env::consts::ARCH, server.qemu, server.topology, self.cpu_vendor)
    }

    fn exec_within(&self, id: &str, arguments: &[String], environment: &[(String, String)], limit: Duration) -> Result<String, EngineError> {
        self.require(id)?;
        let mut call = args(&["exec", &name_of(id)]);
        for (key, value) in environment {
            call.push("--env".into());
            call.push(format!("{key}={value}"));
        }
        call.push("--".into());
        call.extend(arguments.iter().cloned());
        self.runner.run(&call, limit)
    }

    fn find(&self, id: &str) -> Result<Option<Workload>, EngineError> {
        Ok(self.list()?.into_iter().find(|w| w.id == id))
    }

    fn wait_for(&self, id: &str, want: State) -> Result<Workload, EngineError> {
        for _ in 0..self.wait_seconds.max(1) {
            if let Some(found) = self.find(id)? {
                let has_address = found.address.is_some() || found.kind == Kind::Container && false;
                if found.state == want && (want != State::Running || has_address) { return Ok(found); }
            }
            std::thread::sleep(Duration::from_secs(1));
        }
        Err(EngineError::Failed(format!("the machine did not reach {want:?} in time")))
    }

    /// Runs the create calls in order. A GPU container cannot be launched in one call (Incus refuses to add a device that no profile has),
    /// so it is initialised, given its GPU, then started. A VM's CPU model and flags join its launch here, because they need this machine's CPU vendor.
    fn start_new_instance(&self, id: &str, request: &CreateRequest, image: &str) -> Result<(), EngineError> {
        if !list::needs_gpu_device_steps(request) {
            let launch = [launch_arguments(id, request, image), cpu_model_arguments(request, self.cpu_vendor)].concat();
            return self.runner.run(&launch, SLOW).map(|_| ());
        }
        self.runner.run(&init_arguments(id, request, image), SLOW)?;
        self.runner.run(&gpu_device_arguments(id), QUICK)?;
        self.runner.run(&start_arguments(id), SLOW).map(|_| ())
    }

    /// Forgets that the watchdog stopped this container, so a new start begins with a clean slate.
    fn clear_gpu_stop_record(&self, id: &str) -> Result<(), EngineError> {
        for key in [GPU_STOP_CODE_KEY, GPU_STOP_USED_KEY] {
            self.runner.run(&args(&["config", "unset", &name_of(id), key]), QUICK)?;
        }
        Ok(())
    }

    /// Removes an instance whose create did not finish, so no stopped ghost stays behind. Its own failure is not worth hiding the original one.
    fn discard_half_made(&self, id: &str) {
        let _ = self.runner.run(&args(&["delete", &name_of(id), "--force"]), QUICK);
    }

    fn require(&self, id: &str) -> Result<Workload, EngineError> {
        self.find(id)?.ok_or(EngineError::NotFound)
    }
}

impl Engine for IncusEngine {
    fn capabilities(&self) -> Capabilities {
        Capabilities { gpu_in_container: self.gpu_found && gpu::toolkit_ready(self.probe.as_ref()), cpu: self.cpu_offer(), ..self.capabilities }
    }

    fn identity(&self) -> EngineIdentity {
        let mut known = self.version.lock().unwrap();
        if known.is_none() {
            *known = self.runner.run(&args(&["version"]), QUICK).ok().and_then(|text| crate::version::parse_incus_version(&text));
        }
        EngineIdentity { name: ENGINE_NAME.into(), version: known.clone() }
    }

    fn problems(&self) -> Vec<Problem> {
        preflight::incus_host(self.runner.as_ref(), self.probe.as_ref())
    }

    fn list(&self) -> Result<Vec<Workload>, EngineError> {
        Ok(parse_list(&self.runner.run(&args(&["list", "--format", "json"]), QUICK)?))
    }

    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError> {
        let image = request.image.clone().unwrap_or_else(|| self.default_image.clone());
        if let Err(error) = self.start_new_instance(id, request, &image) {
            self.discard_half_made(id);
            return Err(error);
        }
        self.wait_for(id, State::Running).inspect_err(|_| self.discard_half_made(id))
    }

    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError> {
        let workload = self.require(id)?;
        if running && workload.stopped_reason.is_some() { self.clear_gpu_stop_record(id)?; }
        let call = if running { args(&["start", &name_of(id)]) } else { args(&["stop", &name_of(id), "--timeout", STOP_SECONDS]) };
        self.runner.run(&call, SLOW)?;
        self.wait_for(id, if running { State::Running } else { State::Stopped }).map(|_| ())
    }

    /// Exports the instance (its disk and settings) to a tar file the Agent keeps. If it is already gone, there is nothing to keep.
    fn backup(&self, id: &str) -> Result<String, EngineError> {
        self.require(id)?;
        std::fs::create_dir_all(&self.backup_dir)?;
        std::os::unix::fs::PermissionsExt::set_mode(&mut std::fs::metadata(&self.backup_dir)?.permissions(), 0o700);
        let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let file = format!("{id}-{stamp}.tar.gz");
        let path = self.backup_dir.join(&file);
        self.runner.run(&args(&["export", &name_of(id), &path.display().to_string()]), SLOW)?;
        if std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0) == 0 {
            return Err(EngineError::Failed("the backup file is empty, so nothing was deleted".into()));
        }
        Ok(file)
    }

    fn delete(&self, id: &str) -> Result<(), EngineError> {
        self.require(id)?;
        self.runner.run(&args(&["delete", &name_of(id), "--force"]), QUICK)?;
        if self.find(id)?.is_some() { Err(EngineError::Failed("the machine is still there after delete".into())) } else { Ok(()) }
    }

    fn set_bundle_version(&self, id: &str, version: Option<&str>) -> Result<(), EngineError> {
        self.require(id)?;
        let call = match version {
            Some(version) => args(&["config", "set", &name_of(id), BUNDLE_VERSION_KEY, version]),
            None => args(&["config", "unset", &name_of(id), BUNDLE_VERSION_KEY]),
        };
        self.runner.run(&call, QUICK).map(|_| ())
    }

    fn push(&self, id: &str, host_path: &str, container_path: &str) -> Result<(), EngineError> {
        self.require(id)?;
        self.runner.run(&args(&["file", "push", host_path, &format!("{}{container_path}", name_of(id))]), QUICK).map(|_| ())
    }

    fn apply_ssh_keys(&self, id: &str, keys: &KeyList) -> Result<Sshd, EngineError> {
        self.require(id)?;
        let report = self.runner.run_with_input(&ssh_keys::incus_call(&name_of(id)), &keys.file_content(), QUICK)?;
        ssh_keys::parse_state(&report).ok_or_else(|| EngineError::Failed("the workload did not report whether sshd is there".into()))
    }

    fn install_sshd(&self, id: &str) -> Result<InstallReport, EngineError> {
        self.require(id)?;
        let report = self.runner.run(&ssh_install::incus_call(&name_of(id)), INSTALL_TIMEOUT)?;
        ssh_install::parse_report(&report).ok_or_else(|| EngineError::Failed("the workload did not report what happened to the SSH server".into()))
    }

    fn install_app(&self, id: &str, app: App) -> Result<String, EngineError> {
        self.require(id)?;
        self.runner.run_with_input(&apps::incus_call(&name_of(id)), app.script().as_bytes(), apps::INSTALL_TIMEOUT)
    }

    fn attach(&self, id: &str) -> Result<AttachCommand, EngineError> {
        let workload = self.require(id)?;
        if workload.kind == Kind::Vm {
            self.exec_within(id, &attach::agent_probe(), &[], QUICK).map_err(|_| EngineError::Failed(attach::NO_AGENT_MESSAGE.into()))?;
        }
        Ok(AttachCommand { program: self.runner.program(), arguments: attach::arguments(&name_of(id), workload.address.as_deref()) })
    }

    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError> {
        self.exec_within(id, arguments, environment, SLOW)
    }

    fn quick_exec(&self, id: &str, arguments: &[String]) -> Result<String, EngineError> {
        self.exec_within(id, arguments, &[], QUICK)
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod stop_record_tests;

#[cfg(test)]
mod cpu_tests;
