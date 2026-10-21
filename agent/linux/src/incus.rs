//! Workloads as Incus instances: VMs and containers, one engine. Every call is the `incus` program with a fixed argument list;
//! nothing a user typed can become a flag, because names and ids are checked against the id pattern and the image against the image pattern first.
use crate::engine::Engine;
use crate::gpu;
use crate::models::{Capabilities, EngineError, EngineIdentity, GpuMode, Kind, Problem, State, Workload};
use crate::preflight::{self, HostProbe, NoHostChecks};
use crate::validate::CreateRequest;
use serde_json::Value;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const PREFIX: &str = "ms-";
pub const ENGINE_NAME: &str = "incus";
const BUNDLE_VERSION_KEY: &str = "user.metaservice.bundle_version";
const STOP_SECONDS: &str = "30";
const QUICK: Duration = Duration::from_secs(30);
const SLOW: Duration = Duration::from_secs(900);

pub trait Runner: Send + Sync {
    fn run(&self, arguments: &[String], timeout: Duration) -> Result<String, EngineError>;
}

/// The real `incus` program, with a time limit on every call.
pub struct ProcessRunner {
    pub path: String,
}

impl Runner for ProcessRunner {
    fn run(&self, arguments: &[String], timeout: Duration) -> Result<String, EngineError> {
        let mut child = Command::new(&self.path).args(arguments).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
        let mut stdout = child.stdout.take().expect("piped");
        let mut stderr = child.stderr.take().expect("piped");
        let reader = std::thread::spawn(move || { let mut text = String::new(); let _ = stdout.read_to_string(&mut text); text });
        let errors = std::thread::spawn(move || { let mut text = String::new(); let _ = stderr.read_to_string(&mut text); text });
        let deadline = Instant::now() + timeout;
        let status = loop {
            if let Some(status) = child.try_wait()? { break status; }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err(EngineError::Failed(format!("incus {} took too long", arguments.first().map(String::as_str).unwrap_or(""))));
            }
            std::thread::sleep(Duration::from_millis(50));
        };
        let (output, errors) = (reader.join().unwrap_or_default(), errors.join().unwrap_or_default());
        if status.success() { Ok(output) } else { Err(EngineError::Failed(format!("incus {} exited with {}: {}", arguments.first().map(String::as_str).unwrap_or(""), status.code().unwrap_or(-1), errors.chars().rev().take(300).collect::<String>().chars().rev().collect::<String>()))) }
    }
}

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
}

fn name_of(id: &str) -> String {
    format!("{PREFIX}{id}")
}

fn args(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

impl IncusEngine {
    pub fn new(runner: Arc<dyn Runner>, capabilities: Capabilities, backup_dir: PathBuf, default_image: String, wait_seconds: u64) -> Self {
        IncusEngine { runner, capabilities, backup_dir, default_image, wait_seconds, probe: Arc::new(NoHostChecks), gpu_found: false, version: Mutex::new(None) }
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

    fn require(&self, id: &str) -> Result<Workload, EngineError> {
        self.find(id)?.ok_or(EngineError::NotFound)
    }
}

/// The arguments of one `incus launch`. All values are numbers or checked words.
pub fn launch_arguments(id: &str, request: &CreateRequest, image: &str) -> Vec<String> {
    let mut list = vec!["launch".to_string(), image.to_string(), name_of(id)];
    if request.kind == Kind::Vm { list.push("--vm".into()); }
    let settings = [
        format!("limits.cpu={}", request.cpu), format!("limits.memory={}MiB", request.ram_mb), format!("user.metaservice.id={id}"), format!("user.metaservice.name={}", request.name),
        format!("user.metaservice.kind={}", if request.kind == Kind::Vm { "vm" } else { "container" }), format!("user.metaservice.cpu={}", request.cpu),
        format!("user.metaservice.ram_mb={}", request.ram_mb), format!("user.metaservice.disk_gb={}", request.disk_gb),
        format!("user.metaservice.gpu_mode={}", match request.gpu_mode { GpuMode::None => "none", GpuMode::Container => "container", GpuMode::Passthrough => "passthrough" }),
    ];
    for setting in settings {
        list.push("-c".into());
        list.push(setting);
    }
    list.push("-d".into());
    list.push(format!("root,size={}GiB", request.disk_gb));
    if request.gpu_mode == GpuMode::Container {
        list.extend(args(&["-c", "nvidia.runtime=true", "-d", "gpu0,type=gpu"]));
    }
    list
}

/// Reads `incus list --format json`. Only instances this Agent made (they carry user.metaservice.id) are workloads.
pub fn parse_list(text: &str) -> Vec<Workload> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(text) else { return vec![] };
    items.iter().take(5000).filter_map(parse_instance).collect()
}

fn parse_instance(item: &Value) -> Option<Workload> {
    let config = item.get("config")?;
    let text = |key: &str| config.get(format!("user.metaservice.{key}")).and_then(Value::as_str);
    let number = |key: &str| text(key).and_then(|v| v.parse::<u64>().ok());
    Some(Workload {
        id: text("id")?.to_string(),
        name: text("name")?.to_string(),
        kind: if text("kind") == Some("container") { Kind::Container } else { Kind::Vm },
        state: match item.get("status").and_then(Value::as_str) { Some("Running") => State::Running, Some("Stopped") => State::Stopped, Some("Starting" | "Stopping") => State::Provisioning, _ => State::Failed },
        cpu: number("cpu")? as u32,
        ram_mb: number("ram_mb")?,
        disk_gb: number("disk_gb")?,
        gpu_mode: match text("gpu_mode") { Some("container") => GpuMode::Container, Some("passthrough") => GpuMode::Passthrough, _ => GpuMode::None },
        address: address_of(item),
        bundle_version: text("bundle_version").map(str::to_string),
    })
}

/// The first global IPv4 address of any network interface.
fn address_of(item: &Value) -> Option<String> {
    let networks = item.pointer("/state/network")?.as_object()?;
    networks.values().filter_map(|n| n.get("addresses")?.as_array()).flatten()
        .find(|a| a["family"] == "inet" && a["scope"] == "global").and_then(|a| a["address"].as_str()).map(str::to_string)
}

impl Engine for IncusEngine {
    fn capabilities(&self) -> Capabilities {
        Capabilities { gpu_in_container: self.gpu_found && gpu::toolkit_ready(self.probe.as_ref()), ..self.capabilities }
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
        if let Err(error) = self.runner.run(&launch_arguments(id, request, &image), SLOW) {
            let _ = self.runner.run(&args(&["delete", &name_of(id), "--force"]), QUICK);
            return Err(error);
        }
        self.wait_for(id, State::Running).inspect_err(|_| { let _ = self.runner.run(&args(&["delete", &name_of(id), "--force"]), QUICK); })
    }

    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError> {
        self.require(id)?;
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

    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError> {
        self.exec_within(id, arguments, environment, SLOW)
    }

    fn quick_exec(&self, id: &str, arguments: &[String]) -> Result<String, EngineError> {
        self.exec_within(id, arguments, &[], QUICK)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::validate::CreateRequest;

    fn request(kind: Kind, gpu: GpuMode) -> CreateRequest {
        CreateRequest { command_id: "c".into(), name: "demo".into(), kind, cpu: 4, ram_mb: 8192, disk_gb: 50, gpu_mode: gpu, image: None }
    }

    #[test]
    fn launch_arguments_are_one_fixed_shape() {
        let vm = launch_arguments("w-abc", &request(Kind::Vm, GpuMode::None), "images:ubuntu/24.04");
        assert_eq!(&vm[..4], ["launch", "images:ubuntu/24.04", "ms-w-abc", "--vm"]);
        for needed in ["limits.cpu=4", "limits.memory=8192MiB", "user.metaservice.id=w-abc", "root,size=50GiB"] {
            assert!(vm.iter().any(|a| a == needed), "{needed}");
        }
        let container = launch_arguments("w-abc", &request(Kind::Container, GpuMode::None), "images:ubuntu/24.04");
        assert!(!container.contains(&"--vm".to_string()) && !container.iter().any(|a| a.contains("nvidia")));
        let gpu = launch_arguments("w-abc", &request(Kind::Container, GpuMode::Container), "x");
        assert!(gpu.contains(&"nvidia.runtime=true".to_string()) && gpu.contains(&"gpu0,type=gpu".to_string()));
        for flag in ["--privileged", "security.privileged", "raw.lxc", "--target", "-p"] {
            assert!(!vm.iter().chain(&gpu).any(|a| a.contains(flag)), "{flag}");
        }
    }

    /// Answers `incus version` and records every call.
    struct Scripted {
        calls: Mutex<Vec<Vec<String>>>,
        version_answer: Result<String, ()>,
    }

    impl Runner for Scripted {
        fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
            self.calls.lock().unwrap().push(arguments.to_vec());
            match arguments.first().map(String::as_str) {
                Some("version") => self.version_answer.clone().map_err(|_| EngineError::Failed("no".into())),
                Some("list") => Ok(r#"[{"name":"ms-w-1","status":"Running","config":{"user.metaservice.id":"w-1","user.metaservice.name":"d","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1"},"state":null}]"#.into()),
                _ => Ok(String::new()),
            }
        }
    }

    fn engine_with(version_answer: Result<String, ()>) -> (IncusEngine, Arc<Scripted>) {
        let runner = Arc::new(Scripted { calls: Mutex::new(Vec::new()), version_answer });
        let capabilities = Capabilities { vm: false, container: true, gpu_in_vm: false, gpu_in_container: false };
        (IncusEngine::new(runner.clone(), capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1), runner)
    }

    #[test]
    fn the_engine_says_its_name_and_the_version_incus_prints() {
        let (engine, _) = engine_with(Ok("Client version: 6.0.3\nServer version: 6.0.3\n".into()));
        assert_eq!(engine.identity(), EngineIdentity { name: "incus".into(), version: Some("6.0.3".into()) });
    }

    #[test]
    fn a_version_incus_cannot_give_is_none_and_is_asked_again_next_time() {
        let (engine, runner) = engine_with(Err(()));
        assert_eq!(engine.identity().version, None);
        assert_eq!(engine.identity().version, None);
        assert_eq!(runner.calls.lock().unwrap().iter().filter(|c| c[0] == "version").count(), 2);
    }

    #[test]
    fn a_known_version_is_asked_for_once() {
        let (engine, runner) = engine_with(Ok("Server version: 6.1".into()));
        assert_eq!(engine.identity().version.as_deref(), Some("6.1"));
        assert_eq!(engine.identity().version.as_deref(), Some("6.1"));
        assert_eq!(runner.calls.lock().unwrap().iter().filter(|c| c[0] == "version").count(), 1);
    }

    #[test]
    fn clearing_a_workloads_bundle_version_unsets_the_key_and_setting_it_sets_it() {
        let (engine, runner) = engine_with(Ok(String::new()));
        engine.set_bundle_version("w-1", Some("1.2.3")).unwrap();
        engine.set_bundle_version("w-1", None).unwrap();
        let calls = runner.calls.lock().unwrap();
        assert!(calls.contains(&args(&["config", "set", "ms-w-1", "user.metaservice.bundle_version", "1.2.3"])));
        assert!(calls.contains(&args(&["config", "unset", "ms-w-1", "user.metaservice.bundle_version"])));
    }

    #[test]
    fn the_list_is_read_and_only_our_instances_count() {
        let json = r#"[
          {"name":"ms-w-1","status":"Running","config":{"user.metaservice.id":"w-1","user.metaservice.name":"demo","user.metaservice.kind":"container","user.metaservice.cpu":"2",
           "user.metaservice.ram_mb":"2048","user.metaservice.disk_gb":"20","user.metaservice.gpu_mode":"container","user.metaservice.bundle_version":"0.1.0"},
           "state":{"network":{"lo":{"addresses":[{"family":"inet","address":"127.0.0.1","scope":"local"}]},"eth0":{"addresses":[{"family":"inet6","address":"fe80::1","scope":"link"},{"family":"inet","address":"10.1.2.3","scope":"global"}]}}}},
          {"name":"ms-w-2","status":"Stopped","config":{"user.metaservice.id":"w-2","user.metaservice.name":"other","user.metaservice.kind":"vm","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"5"},"state":null},
          {"name":"someone-elses","status":"Running","config":{},"state":null},
          {"name":"broken","status":"Running","config":{"user.metaservice.id":"w-9"}}
        ]"#;
        let found = parse_list(json);
        assert_eq!(found.iter().map(|w| w.id.as_str()).collect::<Vec<_>>(), ["w-1", "w-2"]);
        assert_eq!((found[0].state, found[0].address.as_deref(), found[0].gpu_mode, found[0].bundle_version.as_deref()), (State::Running, Some("10.1.2.3"), GpuMode::Container, Some("0.1.0")));
        assert_eq!((found[1].state, found[1].address.clone(), found[1].kind), (State::Stopped, None, Kind::Vm));
        for junk in ["", "null", "{}", "[1,2]", "garbage"] {
            assert!(parse_list(junk).is_empty(), "{junk}");
        }
    }

    fn write_program(folder: &std::path::Path, name: &str, code: i32) {
        use std::os::unix::fs::PermissionsExt;
        let file = folder.join(name);
        std::fs::write(&file, format!("#!/bin/sh\nexit {code}\n")).unwrap();
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755)).unwrap();
    }

    /// A folder holding fake programs: (file name, exit code). Each one just exits with its code.
    fn fake_programs(programs: &[(&str, i32)]) -> PathBuf {
        let folder = std::env::temp_dir().join(format!("ms-fake-path-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&folder).unwrap();
        programs.iter().for_each(|(name, code)| write_program(&folder, name, *code));
        folder
    }

    fn gpu_engine(programs: &[(&str, i32)], gpu_found: bool) -> IncusEngine {
        let (engine, _) = engine_with(Ok(String::new()));
        engine.with_probe(Arc::new(preflight::SystemProbe::searching(fake_programs(programs)))).with_gpu_found(gpu_found)
    }

    #[test]
    fn containers_get_the_gpu_only_when_a_card_and_a_working_toolkit_are_both_there() {
        assert!(gpu_engine(&[("nvidia-ctk", 0)], true).capabilities().gpu_in_container);
        assert!(gpu_engine(&[("nvidia-container-cli", 0)], true).capabilities().gpu_in_container);
        assert!(!gpu_engine(&[], true).capabilities().gpu_in_container, "card but no toolkit");
        assert!(!gpu_engine(&[("nvidia-ctk", 1)], true).capabilities().gpu_in_container, "a toolkit that fails");
        assert!(!gpu_engine(&[("nvidia-ctk", 0)], false).capabilities().gpu_in_container, "toolkit but no card");
    }

    /// A fake `incus` program: it lists one container, logs every `exec` it gets, and answers nvidia-smi only when told to.
    fn fake_incus(with_smi: bool) -> (IncusEngine, PathBuf) {
        use std::os::unix::fs::PermissionsExt;
        let folder = std::env::temp_dir().join(format!("ms-fake-incus-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&folder).unwrap();
        let (log, program) = (folder.join("calls.log"), folder.join("incus"));
        let list = r#"[{"name":"ms-w-1","status":"Running","config":{"user.metaservice.id":"w-1","user.metaservice.name":"d","user.metaservice.kind":"container","user.metaservice.cpu":"1","user.metaservice.ram_mb":"512","user.metaservice.disk_gb":"1","user.metaservice.gpu_mode":"container"},"state":null}]"#;
        let smi = if with_smi { "echo 'NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB'" } else { "exit 127" };
        let script = format!("#!/bin/sh\necho \"$@\" >> '{}'\ncase \"$1\" in\n  list) echo '{list}' ;;\n  exec) case \"$4\" in nvidia-smi) {smi} ;; ls) printf 'nvidia0\\nnull\\n' ;; *) exit 1 ;; esac ;;\nesac\n", log.display());
        std::fs::write(&program, script).unwrap();
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o755)).unwrap();
        let runner = Arc::new(ProcessRunner { path: program.display().to_string() });
        let capabilities = Capabilities { vm: false, container: true, gpu_in_vm: false, gpu_in_container: false };
        (IncusEngine::new(runner, capabilities, PathBuf::from("/nonexistent"), "images:ubuntu/24.04".into(), 1), log)
    }

    #[test]
    fn the_gpu_check_runs_fixed_incus_exec_calls_and_falls_back_to_the_device_files() {
        for (with_smi, how) in [(true, "nvidia-smi"), (false, "device nodes")] {
            let (engine, log) = fake_incus(with_smi);
            let found = crate::gpu_check::look(&|call| engine.quick_exec("w-1", &call.iter().map(|part| part.to_string()).collect::<Vec<_>>()));
            assert_eq!((found.gpu_visible, found.how), (true, how));
            let calls = std::fs::read_to_string(log).unwrap();
            assert!(calls.contains("exec ms-w-1 -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader"), "{calls}");
            assert_eq!(calls.contains("exec ms-w-1 -- ls /dev"), !with_smi, "{calls}");
        }
    }

    #[test]
    fn installing_the_toolkit_later_is_noticed_without_a_restart() {
        let folder = fake_programs(&[]);
        let (engine, _) = engine_with(Ok(String::new()));
        let engine = engine.with_probe(Arc::new(preflight::SystemProbe::searching(&folder))).with_gpu_found(true);
        assert!(!engine.capabilities().gpu_in_container);
        write_program(&folder, "nvidia-ctk", 0);
        assert!(engine.capabilities().gpu_in_container);
    }
}
