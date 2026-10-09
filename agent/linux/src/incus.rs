//! Workloads as Incus instances: VMs and containers, one engine. Every call is the `incus` program with a fixed argument list;
//! nothing a user typed can become a flag, because names and ids are checked against the id pattern and the image against the image pattern first.
use crate::engine::Engine;
use crate::models::{Capabilities, EngineError, GpuMode, Kind, State, Workload};
use crate::validate::CreateRequest;
use serde_json::Value;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

const PREFIX: &str = "ms-";
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
}

fn name_of(id: &str) -> String {
    format!("{PREFIX}{id}")
}

fn args(items: &[&str]) -> Vec<String> {
    items.iter().map(|s| s.to_string()).collect()
}

impl IncusEngine {
    pub fn new(runner: Arc<dyn Runner>, capabilities: Capabilities, backup_dir: PathBuf, default_image: String, wait_seconds: u64) -> Self {
        IncusEngine { runner, capabilities, backup_dir, default_image, wait_seconds }
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
        self.capabilities
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

    fn set_bundle_version(&self, id: &str, version: &str) -> Result<(), EngineError> {
        self.require(id)?;
        self.runner.run(&args(&["config", "set", &name_of(id), "user.metaservice.bundle_version", version]), QUICK).map(|_| ())
    }

    fn push(&self, id: &str, host_path: &str, container_path: &str) -> Result<(), EngineError> {
        self.require(id)?;
        self.runner.run(&args(&["file", "push", host_path, &format!("{}{container_path}", name_of(id))]), QUICK).map(|_| ())
    }

    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError> {
        self.require(id)?;
        let mut call = args(&["exec", &name_of(id)]);
        for (key, value) in environment {
            call.push("--env".into());
            call.push(format!("{key}={value}"));
        }
        call.push("--".into());
        call.extend(arguments.iter().cloned());
        self.runner.run(&call, SLOW)
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
}
