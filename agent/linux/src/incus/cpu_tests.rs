//! A VM's processors and a container's CPU cap on Incus: the exact create arguments, and what the server's answer to `incus query /1.0` makes this
//! machine offer.
use super::*;
use crate::cpu::CpuFlag;
use crate::models::GpuMode;

const IMAGE: &str = "images:ubuntu/24.04";

fn request(kind: Kind) -> CreateRequest {
    CreateRequest {
        command_id: "c".into(), name: "demo".into(), kind, cpu: 8, ram_mb: 8192, disk_gb: 50, gpu_mode: GpuMode::None, image: None, gpu_memory_gb: None,
        cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None,
    }
}

/// The launch the engine runs: the plain launch, then the CPU model, as `start_new_instance` puts them together.
fn launch(request: &CreateRequest, vendor: Option<CpuVendor>) -> Vec<String> {
    [launch_arguments("w-abc", request, IMAGE), cpu_model_arguments(request, vendor)].concat()
}

/// The value of the `-c key=value` pair with this key.
fn setting<'a>(arguments: &'a [String], key: &str) -> Option<&'a str> {
    arguments.windows(2).filter(|pair| pair[0] == "-c").find_map(|pair| pair[1].strip_prefix(&format!("{key}=")))
}

#[test]
fn a_vm_with_two_sockets_a_model_and_flags_has_exactly_these_arguments() {
    let asked = CreateRequest { cpu_sockets: Some(2), cpu_type: Some("EPYC-Genoa".into()), cpu_flags: vec![(CpuFlag::NestedVirt, false), (CpuFlag::Aes, true)], ..request(Kind::Vm) };
    assert_eq!(launch(&asked, Some(CpuVendor::Amd)), args(&[
        "launch", IMAGE, "ms-w-abc", "--vm", "-c", "limits.cpu=sockets=2,cores=4,threads=1", "-c", "limits.memory=8192MiB", "-c", "user.metaservice.id=w-abc",
        "-c", "user.metaservice.name=demo", "-c", "user.metaservice.kind=vm", "-c", "user.metaservice.cpu=8", "-c", "user.metaservice.ram_mb=8192",
        "-c", "user.metaservice.disk_gb=50", "-c", "user.metaservice.gpu_mode=none", "-c", "user.metaservice.cpu_sockets=2", "-c", "user.metaservice.cpu_type=EPYC-Genoa",
        "-c", "user.metaservice.cpu_flags=nested-virt=off,aes=on", "-d", "root,size=50GiB", "-c", "raw.qemu=-cpu EPYC-Genoa,-svm,-vmx,+aes",
    ]));
}

#[test]
fn the_cores_per_socket_are_cpu_divided_by_the_sockets() {
    for (cpu, sockets, layout) in [(8, 2, "sockets=2,cores=4,threads=1"), (8, 8, "sockets=8,cores=1,threads=1"), (64, 8, "sockets=8,cores=8,threads=1"), (6, 3, "sockets=3,cores=2,threads=1")] {
        let spread = CreateRequest { cpu, cpu_sockets: Some(sockets), ..request(Kind::Vm) };
        let arguments = launch(&spread, None);
        assert_eq!(setting(&arguments, "limits.cpu"), Some(layout));
        assert_eq!(setting(&arguments, "user.metaservice.cpu"), Some(cpu.to_string().as_str()), "the workload still says how many CPUs it has");
        assert!(!arguments.iter().any(|a| a.contains("raw.qemu")), "sockets alone need no QEMU argument");
    }
}

#[test]
fn one_socket_and_the_host_model_leave_the_launch_as_it_was() {
    let before = launch(&request(Kind::Vm), Some(CpuVendor::Amd));
    let same = CreateRequest { cpu_sockets: Some(1), cpu_type: Some("host".into()), ..request(Kind::Vm) };
    assert_eq!(launch(&same, Some(CpuVendor::Amd)), before);
    assert_eq!(setting(&before, "limits.cpu"), Some("8"));
    assert!(!before.iter().any(|a| a.contains("raw.qemu") || a.contains("allowance") || a.contains("user.metaservice.cpu_")), "{before:?}");
}

#[test]
fn a_vm_with_the_host_model_and_aes_off_keeps_its_count_and_gets_one_raw_qemu() {
    let asked = CreateRequest { cpu_type: Some("host".into()), cpu_flags: vec![(CpuFlag::Aes, false)], ..request(Kind::Vm) };
    assert_eq!(launch(&asked, Some(CpuVendor::Intel)), args(&[
        "launch", IMAGE, "ms-w-abc", "--vm", "-c", "limits.cpu=8", "-c", "limits.memory=8192MiB", "-c", "user.metaservice.id=w-abc", "-c", "user.metaservice.name=demo",
        "-c", "user.metaservice.kind=vm", "-c", "user.metaservice.cpu=8", "-c", "user.metaservice.ram_mb=8192", "-c", "user.metaservice.disk_gb=50",
        "-c", "user.metaservice.gpu_mode=none", "-c", "user.metaservice.cpu_flags=aes=off", "-d", "root,size=50GiB", "-c", "raw.qemu=-cpu host,-aes",
    ]));
}

#[test]
fn each_flag_has_its_qemu_words_and_nested_virt_follows_the_vendor() {
    let flagged = |flags: Vec<(CpuFlag, bool)>| CreateRequest { cpu_flags: flags, ..request(Kind::Vm) };
    for (flags, vendor, cpu) in [
        (vec![(CpuFlag::NestedVirt, true)], Some(CpuVendor::Amd), "-cpu host,+svm"), (vec![(CpuFlag::NestedVirt, true)], Some(CpuVendor::Intel), "-cpu host,+vmx"),
        (vec![(CpuFlag::NestedVirt, false)], Some(CpuVendor::Amd), "-cpu host,-svm,-vmx"), (vec![(CpuFlag::NestedVirt, false)], Some(CpuVendor::Intel), "-cpu host,-svm,-vmx"),
        (vec![(CpuFlag::Aes, true)], None, "-cpu host,+aes"), (vec![(CpuFlag::Aes, false)], None, "-cpu host,-aes"),
        (vec![(CpuFlag::NestedVirt, true), (CpuFlag::Aes, true)], Some(CpuVendor::Intel), "-cpu host,+vmx,+aes"),
    ] {
        assert_eq!(cpu_model_arguments(&flagged(flags.clone()), vendor), ["-c".to_string(), format!("raw.qemu={cpu}")], "{flags:?} {vendor:?}");
    }
    let model_only = CreateRequest { cpu_type: Some("Skylake-Server".into()), ..request(Kind::Vm) };
    assert_eq!(cpu_model_arguments(&model_only, None), ["-c", "raw.qemu=-cpu Skylake-Server"]);
    assert!(cpu_model_arguments(&request(Kind::Vm), Some(CpuVendor::Amd)).is_empty(), "nothing asked, nothing added");
}

#[test]
fn a_container_with_a_cap_gets_a_hard_allowance_and_no_qemu() {
    let capped = CreateRequest { cpu: 2, cpu_limit_percent: Some(150), ..request(Kind::Container) };
    assert_eq!(launch(&capped, Some(CpuVendor::Amd)), args(&[
        "launch", IMAGE, "ms-w-abc", "-c", "limits.cpu=2", "-c", "limits.memory=8192MiB", "-c", "user.metaservice.id=w-abc", "-c", "user.metaservice.name=demo",
        "-c", "user.metaservice.kind=container", "-c", "user.metaservice.cpu=2", "-c", "user.metaservice.ram_mb=8192", "-c", "user.metaservice.disk_gb=50",
        "-c", "user.metaservice.gpu_mode=none", "-c", "limits.cpu.allowance=150ms/100ms", "-c", "user.metaservice.cpu_limit_percent=150", "-d", "root,size=50GiB",
    ]));
    let with_gpu = CreateRequest { gpu_mode: GpuMode::Container, ..capped };
    assert_eq!(setting(&init_arguments("w-abc", &with_gpu, IMAGE), "limits.cpu.allowance"), Some("150ms/100ms"), "a GPU container is capped the same way");
}

/// Answers `incus query /1.0` with `server` (None: the call fails), lists one running VM, and records every call.
struct Scripted {
    server: Option<String>,
    calls: Mutex<Vec<Vec<String>>>,
}

const RUNNING_VM: &str = r#"[{"name":"ms-w-abc","status":"Running","config":{"user.metaservice.id":"w-abc","user.metaservice.name":"demo","user.metaservice.kind":"vm","user.metaservice.cpu":"8","user.metaservice.ram_mb":"8192","user.metaservice.disk_gb":"50"},"state":{"network":{"eth0":{"addresses":[{"family":"inet","address":"10.0.0.2","scope":"global"}]}}}}]"#;

impl Runner for Scripted {
    fn run(&self, arguments: &[String], _timeout: Duration) -> Result<String, EngineError> {
        self.calls.lock().unwrap().push(arguments.to_vec());
        match arguments[0].as_str() {
            "query" => self.server.clone().ok_or_else(|| EngineError::Failed("incus is not answering".into())),
            "list" => Ok(RUNNING_VM.into()),
            _ => Ok(String::new()),
        }
    }

    fn run_with_input(&self, arguments: &[String], _input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.run(arguments, timeout)
    }
}

fn over(server: Option<&str>, vendor: Option<CpuVendor>) -> (IncusEngine, Arc<Scripted>) {
    let runner = Arc::new(Scripted { server: server.map(str::to_string), calls: Mutex::new(Vec::new()) });
    let capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu: CpuOffer::HOST_ONLY };
    (IncusEngine::new(runner.clone(), capabilities, PathBuf::from("/nonexistent"), IMAGE.into(), 1).with_cpu_vendor(vendor), runner)
}

fn queries(runner: &Scripted) -> usize {
    runner.calls.lock().unwrap().iter().filter(|call| *call == &server::query_arguments()).count()
}

const SERVER_7_1: &str = r#"{"api_extensions": ["instances", "instance_limits_cpu_topology"], "environment": {"driver": "qemu | lxc", "driver_version": "9.2.4 | 6.0.4"}}"#;

#[test]
fn the_servers_answer_decides_the_models_and_the_sockets_and_is_asked_for_once() {
    let (engine, runner) = over(Some(SERVER_7_1), Some(CpuVendor::Amd));
    let offer = engine.capabilities().cpu;
    assert_eq!(offer, CpuOffer::new(std::env::consts::ARCH, Some((9, 2)), true, Some(CpuVendor::Amd)));
    assert!(offer.topology);
    assert_eq!(engine.capabilities().cpu, offer);
    assert_eq!(queries(&runner), 1);
}

#[test]
fn a_server_that_cannot_answer_offers_nothing_new_and_is_asked_again_next_time() {
    let (engine, runner) = over(None, Some(CpuVendor::Intel));
    let offer = engine.capabilities().cpu;
    assert_eq!((offer.models(), offer.topology), (vec!["host"], false));
    assert_eq!(offer, CpuOffer::new(std::env::consts::ARCH, None, false, Some(CpuVendor::Intel)), "the flags need only the CPU's vendor");
    engine.capabilities();
    assert_eq!(queries(&runner), 2);
    let (refused, _) = over(Some("Error: Get \"http://unix.socket/1.0\": dial unix: connect: permission denied"), None);
    assert_eq!(refused.capabilities().cpu.models(), ["host"]);
}

#[test]
fn a_vm_with_a_model_is_made_in_one_launch_that_carries_the_model() {
    let (engine, runner) = over(None, Some(CpuVendor::Amd));
    let asked = CreateRequest { cpu_type: Some("EPYC".into()), cpu_flags: vec![(CpuFlag::NestedVirt, true)], ..request(Kind::Vm) };
    engine.create("w-abc", &asked).unwrap();
    let calls = runner.calls.lock().unwrap();
    assert_eq!(calls[0], launch(&asked, Some(CpuVendor::Amd)));
    assert_eq!(setting(&calls[0], "raw.qemu"), Some("-cpu EPYC,+svm"));
    assert_eq!(calls.iter().filter(|call| call[0] == "launch").count(), 1);
}
