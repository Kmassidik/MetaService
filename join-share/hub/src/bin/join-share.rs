//! `join-share serve`: public listener + admin listener, unprivileged.
use join_share_hub::clock::system_clock;
use join_share_hub::config::Config;
use join_share_hub::peers::sudo::SudoWg;
use join_share_hub::state::Shared;
use join_share_hub::{http_admin, http_public, startup};
use std::net::SocketAddr;
use std::process::ExitCode;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::signal::unix::{signal, SignalKind};

#[tokio::main]
async fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args != ["serve"] {
        eprintln!("usage: join-share serve");
        return ExitCode::from(2);
    }
    match serve().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(reason) => {
            eprintln!("join-share: {reason}");
            ExitCode::from(1)
        }
    }
}

async fn serve() -> Result<(), String> {
    refuse_root()?;
    let config = Config::from_env()?;
    log_settings();
    let wg = Arc::new(SudoWg::new(config.root_helper.clone(), config.wg_name.clone(), config.pf_anchor.clone(), config.parent_port));
    let state = startup::build_state(config, wg, system_clock())?;
    startup::bring_up(&state)?;
    eprintln!("join-share: admin key is in {}", state.config.state_dir.join("admin.key").display());
    let result = run_listeners(state.clone()).await;
    startup::shut_down(&state);
    result
}

extern "C" {
    fn geteuid() -> u32;
}

/// The hub is unprivileged; only join-share-root (through sudo) is root.
fn refuse_root() -> Result<(), String> {
    // SAFETY: geteuid has no arguments and cannot fail.
    if unsafe { geteuid() } == 0 {
        return Err("refusing to run as root; run as the normal user".into());
    }
    Ok(())
}

/// One line: which settings came from the environment. Names only, never values.
fn log_settings() {
    const NAMES: [&str; 14] = [
        "JOIN_SHARE_NET", "JOIN_SHARE_WG_PORT", "JOIN_SHARE_ENDPOINT", "JOIN_SHARE_PUBLIC_BIND", "JOIN_SHARE_PUBLIC_URL",
        "JOIN_SHARE_ADMIN_BIND", "JOIN_SHARE_PARENT_URL", "JOIN_SHARE_STATE", "JOIN_SHARE_ROOT_HELPER", "JOIN_SHARE_PARENT_DB",
        "JOIN_SHARE_BUILDS_DIR", "JOIN_SHARE_MAC_AGENT", "JOIN_SHARE_WG_NAME", "JOIN_SHARE_PF_ANCHOR",
    ];
    let set: Vec<&str> = NAMES.iter().copied().filter(|n| std::env::var_os(n).is_some()).collect();
    eprintln!("join-share: settings from environment: {}", set.join(", "));
}

async fn run_listeners(state: Shared) -> Result<(), String> {
    let public = bind(state.config.public_bind).await?;
    let admin = bind(state.config.admin_bind).await?;
    eprintln!("join-share: public on {}, admin on {}", state.config.public_bind, state.config.admin_bind);
    let public_app = http_public::router(state.clone()).into_make_service_with_connect_info::<SocketAddr>();
    let admin_app = http_admin::router(state).into_make_service_with_connect_info::<SocketAddr>();
    tokio::select! {
        r = axum::serve(public, public_app) => r.map_err(|e| format!("public listener: {e}")),
        r = axum::serve(admin, admin_app) => r.map_err(|e| format!("admin listener: {e}")),
        _ = stop_signal() => Ok(()),
    }
}

async fn bind(addr: SocketAddr) -> Result<TcpListener, String> {
    TcpListener::bind(addr).await.map_err(|e| format!("cannot listen on {addr}: {e}"))
}

async fn stop_signal() {
    let mut term = match signal(SignalKind::terminate()) {
        Ok(s) => s,
        Err(_) => return std::future::pending().await,
    };
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {}
        _ = term.recv() => {}
    }
}
