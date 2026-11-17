//! The Windows glue: process start-up, the facts' one-time measurement, and the run loop.
//! Everything platform-specific that is not a route lives here, so the rest of the crate
//! stays close to the Linux helper's files.

use crate::config::{Config, Verb};
use crate::facts;
use crate::http::{App, StaticSpecs};
use crate::models::{Specs};
use std::path::PathBuf;

pub const CONTRACT_VERSION: &str = "1.3.0";
const VERSION: &str = crate::config::VERSION;

/// One-time measurement: cores, CPU model, GPU, hardware. RAM and disk are read again per request.
pub fn measure_static() -> StaticSpecs {
    let specs: Specs = facts::measure(find_nvidia_smi());
    StaticSpecs { cpu_cores: specs.cpu_cores, cpu_model: specs.cpu_model, gpu: specs.gpu, hardware: specs.hardware }
}

/// nvidia-smi on PATH, like the Linux helper's finder but with the Windows executable name.
pub fn find_nvidia_smi() -> Option<&'static str> {
    // `where` is the Windows which; a cheap probe keeps the same no-shell rule.
    let ok = std::process::Command::new("where").arg("nvidia-smi").stdin(std::process::Stdio::null()).output().map(|o| o.status.success()).unwrap_or(false);
    ok.then_some("nvidia-smi")
}

/// The entry point: dispatches the verb, and for `run` serves until told to stop.
pub fn run() {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let config = match Config::parse(&arguments) {
        Ok(config) => config,
        Err(why) => {
            eprintln!("metaservice-agent: {why}");
            std::process::exit(2);
        }
    };
    match config.verb {
        Verb::Enroll { root, name, token_file } => {
            if let Err(why) = crate::enroll::run(&root, &name, token_file.as_deref(), &config.state_dir) {
                eprintln!("metaservice-agent: enroll failed: {why}");
                std::process::exit(1);
            }
            println!("enrolled as {name}. It shows as online in the panel in a few seconds.");
        }
        Verb::Setup { yes } => {
            let steps = [
                "Install WireGuard if missing (winget install WireGuard) — needs admin",
                "Install the tunnel service from the join's config — needs admin",
                "Create the scheduled task that starts the helper at logon",
            ];
            for step in steps {
                println!("-> {step}");
            }
            if !yes {
                println!("Run again with --yes to apply.");
                return;
            }
            // The heavy steps are the join script's job (join.ps1); setup only confirms the plan.
            println!("Setup steps are applied by join.ps1; nothing to do here.");
        }
        Verb::Run => run_server(&config),
    }
}

fn run_server(config: &Config) {
    let specs = measure_static();
    let (ram_total_mb, disk_total_gb) = specs_to_budget_input();
    let space = crate::budget::SpaceBudget::new(ram_total_mb, disk_total_gb);
    let token = match crate::files::read_secret(&config.state_dir.join("agent.token")) {
        Ok(token) => token,
        Err(why) => {
            eprintln!("metaservice-agent: {why}");
            std::process::exit(1);
        }
    };
    let app = App::new(specs, token, config.bad_token_limit, Some(config.state_dir.clone()), space);
    let heartbeat = crate::heartbeat::Heartbeat::new(parent_root(&config.state_dir), machine_token(&config.state_dir), config.port, config.heartbeat_seconds, {
        let app = app.clone();
        move || {
            let reading = facts::read_machine()?;
            let specs = app.specs.clone();
            Some(serde_json::json!({
                "facts": {
                    "os": "windows", "arch": std::env::consts::ARCH,
                    "cpu_cores": specs.cpu_cores, "cpu_model": specs.cpu_model,
                    "ram_total_mb": reading.ram_total_mb, "disk_total_gb": reading.disk_total_gb,
                    "free_ram_mb": reading.ram_total_mb.saturating_sub(1024), "free_disk_gb": reading.disk_available_gb,
                    "gpu": specs.gpu, "hardware": specs.hardware,
                    "capabilities": {"vm": false, "container": false, "gpu_in_vm": false, "gpu_in_container": false},
                    "problems": [], "agent_version": VERSION, "agent_build": crate::build::running().unwrap_or_default(),
                    "engine": {"name": crate::engine_windows::NONE_ENGINE, "version": null, "ready": false},
                },
                "workloads": [],
            }))
        }
    });
    heartbeat.spawn();

    let runtime = tokio::runtime::Runtime::new().expect("the tokio runtime could not start");
    runtime.block_on(async move {
        let address = format!("{}:{}", config.bind, config.port);
        let listener = tokio::net::TcpListener::bind(&address).await.unwrap_or_else(|e| panic!("cannot listen on {address}: {e}"));
        println!("metaservice-agent {VERSION} on {address}");
        let router = crate::http::router(app);
        axum::serve(listener, router.into_make_service_with_connect_info::<std::net::SocketAddr>()).await.expect("the server stopped");
    });
}

fn specs_to_budget_input() -> (u64, u64) {
    // RAM and disk totals come from the fresh reading in facts; the budget only needs the shape.
    let reading = facts::read_machine().unwrap_or_else(|| crate::live_space::Reading { ram_total_mb: specs_ram(), disk_total_gb: 1, disk_available_gb: 1 });
    (reading.ram_total_mb, reading.disk_total_gb)
}

fn specs_ram() -> u64 {
    facts::read_machine().map(|r| r.ram_total_mb).unwrap_or(4096)
}

fn parent_root(state_dir: &PathBuf) -> String {
    // The join writes the parent's address into agent.json ("root").
    std::fs::read_to_string(state_dir.join("agent.json")).ok()
        .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
        .and_then(|value| value.get("root").and_then(|r| r.as_str()).map(str::to_string))
        .unwrap_or_else(|| "http://10.77.0.1:9102".into())
}

fn machine_token(state_dir: &PathBuf) -> String {
    std::fs::read_to_string(state_dir.join("agent.token")).map(|t| t.trim().to_string()).unwrap_or_default()
}
