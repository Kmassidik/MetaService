//! The step a delete or create reports, seen through the command the parent polls. Uses the simulated engine, so nothing real is touched.
use crate::budget::SpaceBudget;
use crate::engine::{default_capabilities, Engine, SimulatedEngine};
use crate::models::*;
use crate::service::{BundleInstalling, Service};
use crate::steps;
use crate::validate::{BundleRequest, CreateRequest};
use std::collections::HashMap;
use std::sync::Arc;

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

fn request(command_id: &str, name: &str) -> CreateRequest {
    CreateRequest {
        command_id: command_id.into(), name: name.into(), kind: Kind::Vm, cpu: 1, ram_mb: 512, disk_gb: 1, gpu_mode: GpuMode::None, image: None,
        gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None,
    }
}

fn service(engine: Arc<SimulatedEngine>) -> Arc<Service> {
    let specs = Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, cpu_model: None, ram_total_mb: 16384, disk_total_gb: 500, gpu: Vec::new(), hardware: None };
    Arc::new(Service::new(engine, SpaceBudget::new(16384, 500), specs, "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), Arc::new(NoChat), || None))
}

async fn until(service: &Arc<Service>, id: &str, reached: impl Fn(&Command) -> bool) -> Command {
    for _ in 0..300 {
        if let Some(found) = service.command(id).filter(|c| reached(c)) {
            return found;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("the command did not reach the expected point");
}

fn ended(command: &Command) -> bool {
    command.state != CommandState::Running
}

#[tokio::test]
async fn a_delete_reports_checking_then_backing_up_then_done() {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create("w-1", &request("seed", "one")).unwrap();
    engine.delay_backup();
    let service = service(engine.clone());
    let started = service.delete("d-1", "w-1").await.unwrap();
    assert_eq!(started.step.as_deref(), Some(steps::CHECKING));
    let backing = until(&service, "d-1", |c| c.step.as_deref() == Some(steps::BACKING_UP)).await;
    assert_eq!(backing.state, CommandState::Running);
    engine.release_backup();
    let done = until(&service, "d-1", ended).await;
    assert_eq!(done.state, CommandState::Succeeded);
    assert_eq!(done.step.as_deref(), Some(steps::DONE));
}

#[tokio::test]
async fn a_delete_that_fails_in_the_backup_names_the_backup_step() {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create("w-1", &request("seed", "one")).unwrap();
    engine.fail_backup("export failed");
    let service = service(engine);
    service.delete("d-1", "w-1").await.unwrap();
    let done = until(&service, "d-1", ended).await;
    assert_eq!(done.state, CommandState::Failed);
    assert_eq!(done.step.as_deref(), Some(steps::BACKING_UP));
}

#[tokio::test]
async fn a_delete_that_fails_in_the_delete_names_the_deleting_step() {
    let engine = Arc::new(SimulatedEngine::new(default_capabilities()));
    engine.create("w-1", &request("seed", "one")).unwrap();
    engine.fail_delete("device is busy");
    let service = service(engine);
    service.delete("d-1", "w-1").await.unwrap();
    let done = until(&service, "d-1", ended).await;
    assert_eq!(done.step.as_deref(), Some(steps::DELETING));
}

#[tokio::test]
async fn a_create_starts_in_creating_and_ends_done() {
    let service = service(Arc::new(SimulatedEngine::new(default_capabilities())));
    let started = service.create(request("c-1", "fresh")).await.unwrap();
    assert_eq!(started.step.as_deref(), Some(steps::CREATING));
    let done = until(&service, "c-1", ended).await;
    assert_eq!(done.step.as_deref(), Some(steps::DONE));
}

#[test]
fn a_command_without_steps_leaves_the_field_out() {
    let command = Command { command_id: "s".into(), kind: CommandType::Start, state: CommandState::Running, workload_id: None, result: None, step: None };
    assert!(!serde_json::to_string(&command).unwrap().contains("step"));
}
