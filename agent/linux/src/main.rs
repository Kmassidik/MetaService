//! MetaService Agent for Linux. Runs workloads on this machine for the Root, through Incus.
mod apps;
mod budget;
mod build;
mod bundle;
mod config;
mod console;
mod cpu;
mod cpu_model;
#[cfg(test)]
mod cpu_service_tests;
mod engine;
mod enroll;
mod facts;
mod files;
mod gpu;
mod gpu_check;
mod gpu_watch;
#[cfg(test)]
mod gpu_service_tests;
mod heartbeat;
mod http;
mod images;
mod incus;
mod ledger;
mod live_space;
mod models;
mod preflight;
mod sandbox;
mod service;
mod setup;
mod ssh_install;
#[cfg(test)]
mod ssh_install_tests;
mod ssh_keys;
#[cfg(test)]
mod ssh_keys_tests;
#[cfg(test)]
mod space_service_tests;
mod stats;
mod storage;
mod supervisor;
mod validate;
mod version;

use config::{Config, Verb, VERSION};
use std::net::SocketAddr;
use std::sync::Arc;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let result = Config::parse(&arguments).and_then(|config| match config.verb.clone() {
        Verb::Enroll { root, name, token_file } => enroll::run(&config, &root, &name, token_file.as_deref()),
        Verb::Setup { yes, user } => run_setup(yes, user),
        Verb::SandboxRunner => run_sandbox_runner(&config),
        Verb::Run => run(config),
    });
    if let Err(message) = result {
        eprintln!("metaservice-agent: {message}");
        std::process::exit(1);
    }
}

/// `setup`: print the plan for this distro, and apply it only with --yes and as root.
fn run_setup(yes: bool, user: Option<String>) -> Result<(), String> {
    let os_release = std::fs::read_to_string("/etc/os-release").map_err(|e| format!("cannot read /etc/os-release: {e}"))?;
    let family = setup::family_from_os_release(&os_release).ok_or("this Linux family is not supported by setup yet (Fedora/RHEL and Debian/Ubuntu are)")?;
    let user = user.or_else(|| std::env::var("SUDO_USER").ok()).ok_or("say which user runs the Agent: --user NAME")?;
    let steps = setup::plan(family, &user)?;
    println!("Setup plan for this machine (the Agent runs as {user}):");
    for (number, step) in steps.iter().enumerate() {
        println!("  {}. {}", number + 1, step.describe());
    }
    if !yes {
        println!("Nothing was changed. Run again as root with --yes to apply.");
        return Ok(());
    }
    if unsafe { libc::geteuid() } != 0 {
        return Err("setup --yes must run as root".into());
    }
    setup::execute(&steps, &setup::RealHost, &mut |line| println!("{line}"))?;
    println!("Done. Log in again so the new group applies, then start the Agent.");
    Ok(())
}

fn root_address(config: &Config) -> Option<String> {
    let settings: serde_json::Value = serde_json::from_slice(&std::fs::read(config.settings_file()).ok()?).ok()?;
    enroll::valid_root(settings["root"].as_str()?).ok()
}

fn find_incus(config: &Config) -> Result<String, String> {
    config.incus_path.clone().or_else(|| ["/usr/bin/incus", "/usr/local/bin/incus", "/run/current-system/sw/bin/incus"].iter().find(|p| std::path::Path::new(p).is_file()).map(|p| p.to_string()))
        .filter(|p| std::path::Path::new(p).is_file()).ok_or_else(|| "the `incus` program was not found; install Incus or pass --incus-path".to_string())
}

/// Starts the GPU memory watchdog when this machine runs Incus and has an NVIDIA card it can read.
fn start_gpu_watch(config: &Config, specs: &models::Specs) -> Result<(), String> {
    let Some(nvidia_smi) = facts::find_nvidia_smi().filter(|_| !specs.gpu.is_empty() && config.engine != "simulated") else { return Ok(()) };
    gpu_watch::spawn(Arc::new(incus::ProcessRunner { path: find_incus(config)? }), nvidia_smi);
    Ok(())
}

fn make_engine(config: &Config, specs: &models::Specs) -> Result<Arc<dyn engine::Engine>, String> {
    if config.engine == "simulated" {
        return Ok(Arc::new(engine::SimulatedEngine::new(engine::default_capabilities())));
    }
    let path = find_incus(config)?;
    let capabilities = models::Capabilities { vm: std::path::Path::new("/dev/kvm").exists(), container: true, gpu_in_vm: false, gpu_in_container: false, cpu: cpu::CpuOffer::HOST_ONLY, sandbox: false };
    let backups = config.backup_dir.clone().unwrap_or_else(|| config.state_dir.join("backups"));
    Ok(Arc::new(incus::IncusEngine::new(Arc::new(incus::ProcessRunner { path }), capabilities, backups, config.default_image.clone(), 120).with_probe(Arc::new(preflight::SystemProbe::default())).with_gpu_found(!specs.gpu.is_empty()).with_cpu_vendor(cpu::this_machines_vendor())))
}

/// The sandbox engine this helper runs. None unless `--sandbox` says so, which is what a machine that cannot run sandboxes must say: its facts carry no
/// `sandbox` block and every sandbox route is a 404.
fn make_sandboxes(config: &Config, specs: &models::Specs, budget: &budget::SpaceBudget) -> Arc<sandbox::Sandboxes> {
    match config.sandbox.as_deref() {
        Some(sandbox::SIMULATED) => sandbox::Sandboxes::simulated(sandbox::Limits::of(specs, budget)),
        Some(sandbox::firecracker::engine::NAME) => firecracker_sandboxes(config, specs, budget),
        _ => sandbox::Sandboxes::disabled(),
    }
}

/// The real engine. A runner that cannot be reached, no KVM, or no base template is not a reason to fail the helper: it answers as a machine that cannot
/// run sandboxes, with the reason in its own log, and the Root places no sandbox on it.
fn firecracker_sandboxes(config: &Config, specs: &models::Specs, budget: &budget::SpaceBudget) -> Arc<sandbox::Sandboxes> {
    let socket = config.sandbox_runner_socket.clone().unwrap_or_else(|| sandbox::firecracker::SOCKET.into());
    let machine = sandbox::firecracker::engine::Machine {
        kernel: config.sandbox_kernel.clone().unwrap_or_else(|| sandbox::firecracker::KERNEL.into()),
        rootfs: config.sandbox_rootfs.clone().unwrap_or_else(|| sandbox::firecracker::ROOTFS.into()),
        ..sandbox::firecracker::engine::Machine::default()
    };
    let runner: Arc<dyn sandbox::runner::Runner> = Arc::new(sandbox::runner::RunnerClient::new(socket));
    match sandbox::firecracker::FirecrackerSandboxEngine::connect(runner, sandbox::Limits::of(specs, budget), machine) {
        Ok(engine) => sandbox::Sandboxes::running(Arc::new(engine)),
        Err(cause) => {
            eprintln!("sandboxes: this helper cannot run sandboxes: {cause}");
            sandbox::Sandboxes::disabled()
        }
    }
}

/// `--sandbox-runner`: the root half of the engine, as the same program in another mode. It refuses to run without root, because every step it knows is
/// one that needs it.
fn run_sandbox_runner(config: &Config) -> Result<(), String> {
    // SAFETY: `geteuid` reads one process-wide number and changes nothing.
    if unsafe { libc::geteuid() } != 0 {
        return Err("the sandbox runner must run as root: it makes namespaces, taps, firewall rules and jails".into());
    }
    sandbox::runner::Server::new(runner_settings(config))?.listen()
}

/// What the runner is told at the machine: everything else is a constant of this build.
fn runner_settings(config: &Config) -> sandbox::runner::Settings {
    let defaults = sandbox::runner::Settings::default();
    sandbox::runner::Settings {
        socket: config.sandbox_runner_socket.clone().unwrap_or(defaults.socket),
        run_dir: config.sandbox_runner_dir.clone().unwrap_or(defaults.run_dir),
        uplink: config.sandbox_runner_uplink.clone().unwrap_or(defaults.uplink),
        kernel: config.sandbox_kernel.clone().unwrap_or(defaults.kernel),
        rootfs: config.sandbox_rootfs.clone().unwrap_or(defaults.rootfs),
    }
}

fn run(config: Config) -> Result<(), String> {
    use std::os::unix::fs::DirBuilderExt;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&config.state_dir).map_err(|e| e.to_string())?;
    let command_token = files::read_secret(&config.command_token_file())?;
    let root = root_address(&config);
    let machine_token = match &root { Some(_) => Some(files::read_secret(&config.token_file())?), None => None };
    let specs = facts::measure(facts::find_nvidia_smi().as_deref());
    let mut budget = budget::SpaceBudget::new(specs.ram_total_mb, specs.disk_total_gb);
    budget.ram_allowance_mb = config.ram_allowance_mb;
    budget.disk_allowance_gb = config.disk_allowance_gb;
    budget.reserve_ram_mb = config.reserve_ram_mb.unwrap_or(budget.reserve_ram_mb);
    budget.reserve_disk_gb = config.reserve_disk_gb.unwrap_or(budget.reserve_disk_gb);
    budget.reserve_ram_pinned = config.reserve_ram_mb.is_some();
    budget.reserve_disk_pinned = config.reserve_disk_gb.is_some();
    let engine = make_engine(&config, &specs)?;
    let sandboxes = make_sandboxes(&config, &specs, &budget);
    start_gpu_watch(&config, &specs)?;
    let supervisor = (std::env::var("MS_NO_CHAT").is_err()).then(|| config.python_path.clone().or_else(bundle::find_python)).flatten()
        .map(|python| supervisor::Supervisor::new(python, config.state_dir.join("chat.log")));
    let installer = bundle::BundleInstaller::new(config.clone(), engine.clone(), root.clone(), machine_token.clone(), supervisor.clone());
    installer.resume();
    let ledger = Arc::new(ledger::Ledger::new(2000, Some(config.state_dir.join("commands.json"))));
    let service = Arc::new(service::Service::new(engine, budget, specs, VERSION, ledger, installer, facts::read_machine).with_build(build::running()).with_sandboxes(sandboxes));
    let runtime = tokio::runtime::Builder::new_multi_thread().enable_all().build().map_err(|e| e.to_string())?;
    if let (Some(root), Some(token)) = (root, machine_token) {
        let heartbeat = heartbeat::Heartbeat::new(root, token, config.port, config.heartbeat_seconds);
        let nudge = heartbeat.clone();
        service.set_on_change(Arc::new(move || nudge.beat_soon()));
        heartbeat.spawn(service.clone(), runtime.handle().clone());
    }
    let app = http::App::new(service, command_token, config.bad_token_limit);
    runtime.block_on(serve(app, &config, supervisor))
}

async fn serve(app: Arc<http::App>, config: &Config, supervisor: Option<Arc<supervisor::Supervisor>>) -> Result<(), String> {
    let address: SocketAddr = format!("{}:{}", config.bind, config.port).parse().map_err(|_| "bad --bind or --port".to_string())?;
    let listener = tokio::net::TcpListener::bind(address).await.map_err(|e| format!("cannot listen on {address}: {e}"))?;
    println!("metaservice-agent {VERSION} on {address}");
    let shutdown = async move {
        let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).expect("signal handler");
        tokio::select! { _ = terminate.recv() => {}, _ = tokio::signal::ctrl_c() => {} }
        if let Some(supervisor) = supervisor { supervisor.stop(); }
    };
    axum::serve(listener, http::router(app).into_make_service_with_connect_info::<SocketAddr>()).with_graceful_shutdown(shutdown).await.map_err(|e| e.to_string())
}
