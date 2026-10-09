//! MetaService Agent for Linux. Runs workloads on this machine for the Root, through Incus.
mod bundle;
mod budget;
mod config;
mod engine;
mod enroll;
mod facts;
mod files;
mod heartbeat;
mod http;
mod incus;
mod ledger;
mod models;
mod service;
mod supervisor;
mod validate;

use config::{Config, Verb, VERSION};
use std::net::SocketAddr;
use std::sync::Arc;

fn main() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let result = Config::parse(&arguments).and_then(|config| match config.verb.clone() {
        Verb::Enroll { root, name, token_file } => enroll::run(&config, &root, &name, token_file.as_deref()),
        Verb::Run => run(config),
    });
    if let Err(message) = result {
        eprintln!("metaservice-agent: {message}");
        std::process::exit(1);
    }
}

fn root_address(config: &Config) -> Option<String> {
    let settings: serde_json::Value = serde_json::from_slice(&std::fs::read(config.settings_file()).ok()?).ok()?;
    enroll::valid_root(settings["root"].as_str()?).ok()
}

fn make_engine(config: &Config, specs: &models::Specs) -> Result<Arc<dyn engine::Engine>, String> {
    if config.engine == "simulated" {
        return Ok(Arc::new(engine::SimulatedEngine::new(engine::default_capabilities())));
    }
    let path = config.incus_path.clone().or_else(|| ["/usr/bin/incus", "/usr/local/bin/incus", "/run/current-system/sw/bin/incus"].iter().find(|p| std::path::Path::new(p).is_file()).map(|p| p.to_string()))
        .filter(|p| std::path::Path::new(p).is_file()).ok_or("the `incus` program was not found; install Incus or pass --incus-path")?;
    let capabilities = models::Capabilities { vm: std::path::Path::new("/dev/kvm").exists(), container: true, gpu_in_vm: false, gpu_in_container: !specs.gpu.is_empty() };
    let backups = config.backup_dir.clone().unwrap_or_else(|| config.state_dir.join("backups"));
    Ok(Arc::new(incus::IncusEngine::new(Arc::new(incus::ProcessRunner { path }), capabilities, backups, config.default_image.clone(), 120)))
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
    let engine = make_engine(&config, &specs)?;
    let supervisor = (std::env::var("MS_NO_CHAT").is_err()).then(|| config.python_path.clone().or_else(bundle::find_python)).flatten()
        .map(|python| supervisor::Supervisor::new(python, config.state_dir.join("chat.log")));
    let installer = bundle::BundleInstaller::new(config.clone(), engine.clone(), root.clone(), machine_token.clone(), supervisor.clone());
    installer.resume();
    let ledger = Arc::new(ledger::Ledger::new(2000, Some(config.state_dir.join("commands.json"))));
    let service = Arc::new(service::Service::new(engine, budget, specs, VERSION, ledger, installer, facts::available_disk_gb));
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
