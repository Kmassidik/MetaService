//! The MetaService helper for Windows, thin v1: joins the parent over WireGuard, reports stats,
//! opens a host terminal (PowerShell), updates itself and cleans up. It runs no VMs:
//! Windows has no Incus equivalent, so the engine here is `WindowsEngine` and the panel
//! refuses VM creation on this OS with a plain message.
//!
//! Structure mirrors `agent/linux`: the portable files (models, facts, validate, budget, ledger,
//! heartbeat) are shared; `platform.rs`, `engine_windows.rs`, `conpty.rs` and the trimmed config
//! hold the Windows glue.

mod budget;
mod build;
mod conpty;
mod config;
mod cpu;
mod cpu_model;
mod engine;
mod engine_windows;
mod enroll;
mod facts;
mod files;
mod gpu;
mod gpu_check;
mod hardware;
mod heartbeat;
mod http;
mod ledger;
mod ssh_install;
mod ssh_keys;
mod live_space;
mod models;
mod platform;
mod probe;
mod validate;
mod version;

fn main() {
    platform::run();
}
