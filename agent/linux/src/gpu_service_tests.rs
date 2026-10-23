//! The Service on the GPU paths: a container that asks for the GPU, and the check inside it. Uses the simulated engine, so nothing real is touched.
use crate::budget::SpaceBudget;
use crate::engine::{default_capabilities, SimulatedEngine};
use crate::models::*;
use crate::service::{BundleInstalling, Failure, Service};
use crate::validate::{BundleRequest, CreateRequest};
use std::collections::HashMap;
use std::sync::Arc;

/// An installer that does nothing: only the GPU paths are looked at here.
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

async fn finished(service: &Arc<Service>, id: &str) -> Command {
    for _ in 0..200 {
        if let Some(found) = service.command(id).filter(|c| c.state != CommandState::Running) {
            return found;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("the command did not finish");
}

fn gpu_service(gpu_in_container: bool) -> Arc<Service> {
    let gpu = vec![Gpu { vendor: "nvidia".into(), model: "NVIDIA GeForce RTX 5090".into(), memory_mb: Some(32768) }];
    let specs = Specs { os: "linux".into(), arch: "x86_64".into(), cpu_cores: 4, ram_total_mb: 65536, disk_total_gb: 2000, gpu };
    let engine = Arc::new(SimulatedEngine::new(Capabilities { gpu_in_container, ..default_capabilities() }));
    Arc::new(Service::new(engine, SpaceBudget::new(65536, 2000), specs, "0.9.9", Arc::new(crate::ledger::Ledger::new(100, None)), Arc::new(NoChat), || None))
}

fn gpu_container_request(command_id: &str) -> CreateRequest {
    CreateRequest { command_id: command_id.into(), name: "gpu-box".into(), kind: Kind::Container, cpu: 2, ram_mb: 2048, disk_gb: 10, gpu_mode: GpuMode::Container, image: None, gpu_memory_gb: None, cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None }
}

#[tokio::test]
async fn a_gpu_container_without_the_toolkit_is_refused_in_plain_words() {
    let refused = gpu_service(false).create(gpu_container_request("g-1")).await.err().expect("refused");
    let Failure::Refused(refusal) = refused else { panic!("expected a refusal") };
    assert_eq!(refusal.message, crate::gpu::NO_TOOLKIT_MESSAGE);
}

async fn made(service: &Arc<Service>, request: CreateRequest) -> String {
    let id = request.command_id.clone();
    let started = service.create(request).await.ok().unwrap();
    finished(service, &id).await;
    started.workload_id.unwrap()
}

#[tokio::test]
async fn the_gpu_check_answers_without_looking_inside_a_vm_or_a_container_without_the_gpu() {
    let service = gpu_service(true);
    let plain = CreateRequest { gpu_mode: GpuMode::None, ..gpu_container_request("p-1") };
    let vm = CreateRequest { kind: Kind::Vm, gpu_mode: GpuMode::None, ..gpu_container_request("p-2") };
    for request in [plain, vm] {
        let id = made(&service, request).await;
        assert_eq!(service.gpu_check(&id).await.ok().unwrap(), crate::gpu_check::not_given());
    }
}

#[tokio::test]
async fn the_gpu_check_looks_inside_a_running_gpu_container_and_says_what_it_found() {
    let service = gpu_service(true);
    let id = made(&service, gpu_container_request("c-1")).await;
    let answer = service.gpu_check(&id).await.ok().unwrap();
    assert_eq!((answer.gpu_visible, answer.how), (false, "none"), "the simulated container prints nothing");
}

#[tokio::test]
async fn the_gpu_check_needs_a_running_container_that_exists() {
    let service = gpu_service(true);
    let id = made(&service, gpu_container_request("c-2")).await;
    service.set_running("stop-1", &id, false).await.ok().unwrap();
    let Err(Failure::Refused(refusal)) = service.gpu_check(&id).await else { panic!("expected a refusal") };
    assert_eq!(refusal.code, "not_running");
    assert!(matches!(service.gpu_check("w-none").await, Err(Failure::NotFound)));
}

#[tokio::test]
async fn a_gpu_container_with_the_toolkit_is_accepted() {
    let service = gpu_service(true);
    service.create(gpu_container_request("g-2")).await.ok().unwrap();
    assert_eq!(finished(&service, "g-2").await.state, CommandState::Succeeded);
}
