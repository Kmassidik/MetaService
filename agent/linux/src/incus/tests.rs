//! Tests of the Incus engine: launch arguments, version, bundle key, list parsing and the GPU checks.
use super::*;
use crate::models::GpuMode;
use crate::validate::CreateRequest;
use std::path::PathBuf;

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
    fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.run(arguments, timeout)
    }

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
