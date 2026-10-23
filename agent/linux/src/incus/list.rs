//! The shapes `incus` speaks: the arguments of one launch and the JSON of `incus list`.
use super::{args, name_of};
use crate::models::{GpuMode, Kind, State, StoppedReason, Workload, GPU_OVER_LIMIT_CODE};
use crate::validate::CreateRequest;
use serde_json::Value;

/// The container runtime flag a GPU container needs at create time.
const NVIDIA_RUNTIME_SETTING: &str = "nvidia.runtime=true";
/// The device name and type the GPU is added under, after the container exists.
const GPU_DEVICE_NAME: &str = "gpu0";
const GPU_DEVICE_TYPE: &str = "gpu";
/// The config keys of the GPU memory limit and of the watchdog's stop record (the record is cleared when the container starts again).
pub const GPU_MEMORY_KEY: &str = "user.metaservice.gpu_memory_gb";
pub const GPU_STOP_CODE_KEY: &str = "user.metaservice.gpu_stop_code";
pub const GPU_STOP_USED_KEY: &str = "user.metaservice.gpu_stop_used_mib";

/// True when the container gets its GPU through `init` + `device add` + `start` (a launch cannot add a device that no profile has).
pub fn needs_gpu_device_steps(request: &CreateRequest) -> bool {
    request.kind == Kind::Container && request.gpu_mode == GpuMode::Container
}

/// The arguments of one `incus launch`. All values are numbers or checked words.
pub fn launch_arguments(id: &str, request: &CreateRequest, image: &str) -> Vec<String> {
    creation_arguments("launch", id, request, image)
}

/// The arguments of `incus init`: the same instance as a launch, left stopped. A GPU container also gets the NVIDIA runtime here.
pub fn init_arguments(id: &str, request: &CreateRequest, image: &str) -> Vec<String> {
    let mut list = creation_arguments("init", id, request, image);
    if request.gpu_mode == GpuMode::Container { list.extend(args(&["-c", NVIDIA_RUNTIME_SETTING])); }
    if let Some(limit) = request.gpu_memory_gb { list.extend(args(&["-c", &format!("{GPU_MEMORY_KEY}={limit}")])); }
    list
}

/// The arguments that add the GPU to an existing container.
pub fn gpu_device_arguments(id: &str) -> Vec<String> {
    vec!["config".into(), "device".into(), "add".into(), name_of(id), GPU_DEVICE_NAME.into(), GPU_DEVICE_TYPE.into()]
}

pub fn start_arguments(id: &str) -> Vec<String> {
    vec!["start".into(), name_of(id)]
}

fn creation_arguments(verb: &str, id: &str, request: &CreateRequest, image: &str) -> Vec<String> {
    let mut list = vec![verb.to_string(), image.to_string(), name_of(id)];
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
    let state = match item.get("status").and_then(Value::as_str) { Some("Running") => State::Running, Some("Stopped") => State::Stopped, Some("Starting" | "Stopping") => State::Provisioning, _ => State::Failed };
    let gpu_memory_gb = number("gpu_memory_gb").and_then(|gb| u32::try_from(gb).ok());
    Some(Workload {
        id: text("id")?.to_string(),
        name: text("name")?.to_string(),
        kind: if text("kind") == Some("container") { Kind::Container } else { Kind::Vm },
        state,
        cpu: number("cpu")? as u32,
        ram_mb: number("ram_mb")?,
        disk_gb: number("disk_gb")?,
        gpu_mode: match text("gpu_mode") { Some("container") => GpuMode::Container, Some("passthrough") => GpuMode::Passthrough, _ => GpuMode::None },
        address: address_of(item),
        bundle_version: text("bundle_version").map(str::to_string),
        gpu_memory_gb,
        stopped_reason: gpu_stop_reason(state, gpu_memory_gb, text("gpu_stop_code"), number("gpu_stop_used_mib")),
    })
}

/// The watchdog's stop, read back from the instance settings. Only reported while the instance is stopped.
fn gpu_stop_reason(state: State, limit_gb: Option<u32>, code: Option<&str>, used_mib: Option<u64>) -> Option<StoppedReason> {
    (state == State::Stopped && code == Some(GPU_OVER_LIMIT_CODE)).then_some(())?;
    Some(StoppedReason::gpu_memory_over_limit(used_mib?, limit_gb?))
}

/// The first global IPv4 address of any network interface.
fn address_of(item: &Value) -> Option<String> {
    let networks = item.pointer("/state/network")?.as_object()?;
    networks.values().filter_map(|n| n.get("addresses")?.as_array()).flatten()
        .find(|a| a["family"] == "inet" && a["scope"] == "global").and_then(|a| a["address"].as_str()).map(str::to_string)
}
