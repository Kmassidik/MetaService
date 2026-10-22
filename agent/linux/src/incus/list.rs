//! The shapes `incus` speaks: the arguments of one launch and the JSON of `incus list`.
use super::{args, name_of};
use crate::models::{GpuMode, Kind, State, Workload};
use crate::validate::CreateRequest;
use serde_json::Value;

/// The arguments of one `incus launch`. All values are numbers or checked words.
pub fn launch_arguments(id: &str, request: &CreateRequest, image: &str) -> Vec<String> {
    let mut list = vec!["launch".to_string(), image.to_string(), name_of(id)];
    if request.kind == Kind::Vm { list.push("--vm".into()); }
    let settings = [
        format!("limits.cpu={}", request.cpu), format!("limits.memory={}MiB", request.ram_mb), format!("user.metaservice.id={id}"), format!("user.metaservice.name={}", request.name),
        format!("user.metaservice.kind={}", if request.kind == Kind::Vm { "vm" } else { "container" }), format!("user.metaservice.cpu={}", request.cpu),
        format!("user.metaservice.ram_mb={}", request.ram_mb), format!("user.metaservice.disk_gb={}", request.disk_gb),
        format!("user.metaservice.gpu_mode={}", match request.gpu_mode { GpuMode::None => "none", GpuMode::Container => "container", GpuMode::Passthrough => "passthrough" }),
    ];
    for setting in settings {
        list.push("-c".into());
        list.push(setting);
    }
    list.push("-d".into());
    list.push(format!("root,size={}GiB", request.disk_gb));
    if request.gpu_mode == GpuMode::Container {
        list.extend(args(&["-c", "nvidia.runtime=true", "-d", "gpu0,type=gpu"]));
    }
    list
}

/// Reads `incus list --format json`. Only instances this Agent made (they carry user.metaservice.id) are workloads.
pub fn parse_list(text: &str) -> Vec<Workload> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(text) else { return vec![] };
    items.iter().take(5000).filter_map(parse_instance).collect()
}

fn parse_instance(item: &Value) -> Option<Workload> {
    let config = item.get("config")?;
    let text = |key: &str| config.get(format!("user.metaservice.{key}")).and_then(Value::as_str);
    let number = |key: &str| text(key).and_then(|v| v.parse::<u64>().ok());
    Some(Workload {
        id: text("id")?.to_string(),
        name: text("name")?.to_string(),
        kind: if text("kind") == Some("container") { Kind::Container } else { Kind::Vm },
        state: match item.get("status").and_then(Value::as_str) { Some("Running") => State::Running, Some("Stopped") => State::Stopped, Some("Starting" | "Stopping") => State::Provisioning, _ => State::Failed },
        cpu: number("cpu")? as u32,
        ram_mb: number("ram_mb")?,
        disk_gb: number("disk_gb")?,
        gpu_mode: match text("gpu_mode") { Some("container") => GpuMode::Container, Some("passthrough") => GpuMode::Passthrough, _ => GpuMode::None },
        address: address_of(item),
        bundle_version: text("bundle_version").map(str::to_string),
    })
}

/// The first global IPv4 address of any network interface.
fn address_of(item: &Value) -> Option<String> {
    let networks = item.pointer("/state/network")?.as_object()?;
    networks.values().filter_map(|n| n.get("addresses")?.as_array()).flatten()
        .find(|a| a["family"] == "inet" && a["scope"] == "global").and_then(|a| a["address"].as_str()).map(str::to_string)
}
