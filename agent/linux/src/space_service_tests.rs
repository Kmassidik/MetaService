//! The facts the heartbeat sends and the create check both follow the machine as it is now, not as it was at start.
use crate::budget::SpaceBudget;
use crate::engine::{default_capabilities, SimulatedEngine};
use crate::live_space::Reading;
use crate::models::*;
use crate::service::{BundleInstalling, Failure, Service};
use crate::validate::{BundleRequest, CreateRequest};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

struct NoChat;

impl BundleInstalling for NoChat {
    fn install(&self, _request: &BundleRequest) -> Result<HashMap<String, String>, String> {
        Ok(HashMap::new())
    }

    fn uninstall(&self, _workload_id: Option<&str>) -> Result<(), String> {
        Ok(())
    }

    fn installed_version(&self) -> Option<String> {
        None
    }
}

const RAM_MB: u64 = 65536;

fn reading(disk_total_gb: u64) -> Reading {
    Reading { ram_total_mb: RAM_MB, disk_total_gb, disk_available_gb: disk_total_gb }
}

/// A service whose reader hands out the shared reading, so a test can change the machine between two calls.
fn service_over(machine: Arc<Mutex<Reading>>) -> Arc<Service> {
    let specs = Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, ram_total_mb: RAM_MB, disk_total_gb: 105, gpu: Vec::new() };
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    let ledger = Arc::new(crate::ledger::Ledger::new(100, None));
    Arc::new(Service::new(engine, SpaceBudget::new(RAM_MB, 105), specs, "0.9.9", ledger, Arc::new(NoChat), move || Some(*machine.lock().unwrap())))
}

fn request(command_id: &str, disk_gb: u64) -> CreateRequest {
    CreateRequest { command_id: command_id.into(), name: "box".into(), kind: Kind::Container, cpu: 1, ram_mb: 512, disk_gb, gpu_mode: GpuMode::None, image: None, gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None }
}

#[tokio::test]
async fn two_heartbeats_report_the_volume_before_and_after_it_grew() {
    let machine = Arc::new(Mutex::new(reading(105)));
    let service = service_over(machine.clone());
    let before = service.facts().await.ok().expect("facts");
    assert_eq!((before.disk_total_gb, before.free_disk_gb), (105, 55));
    *machine.lock().unwrap() = reading(981);
    let after = service.facts().await.ok().expect("facts");
    assert_eq!((after.disk_total_gb, after.free_disk_gb), (981, 981 - 196 - 20));
}

#[tokio::test]
async fn a_create_that_did_not_fit_before_the_volume_grew_fits_after() {
    let machine = Arc::new(Mutex::new(reading(105)));
    let service = service_over(machine.clone());
    let refused = service.create(request("big-1", 300)).await.err().expect("refused");
    assert!(matches!(refused, Failure::Refused(_)));
    *machine.lock().unwrap() = reading(981);
    assert!(service.create(request("big-2", 300)).await.is_ok());
}
