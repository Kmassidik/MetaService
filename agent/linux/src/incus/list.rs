//! The shapes `incus` speaks: the arguments of one launch and the JSON of `incus list`.
use super::{args, name_of};
use crate::cpu::{CpuFlag, CpuVendor, HOST_MODEL};
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
/// What was asked of the processors, recorded only when asked. Never read back into the workload: the Root's parser refuses unknown workload fields.
const CPU_SOCKETS_KEY: &str = "user.metaservice.cpu_sockets";
const CPU_TYPE_KEY: &str = "user.metaservice.cpu_type";
const CPU_FLAGS_KEY: &str = "user.metaservice.cpu_flags";
const CPU_LIMIT_KEY: &str = "user.metaservice.cpu_limit_percent";
/// A container's CPU cap is CPU time per period of this many ms, so P percent is `Pms/100ms` (Incus' hard limit; a bare `P%` is only a share).
const CPU_PERIOD_MS: u32 = 100;

/// True when the container gets its GPU through `init` + `device add` + `start` (a launch cannot add a device that no profile has).
pub fn needs_gpu_device_steps(request: &CreateRequest) -> bool {
    request.kind == Kind::Container && request.gpu_mode == GpuMode::Container
}

/// The arguments of one `incus launch`. All values are numbers or checked words. A VM's CPU model and flags come after them (`cpu_model_arguments`).
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
        format!("limits.cpu={}", cpu_limit(request)), format!("limits.memory={}MiB", request.ram_mb), format!("user.metaservice.id={id}"), format!("user.metaservice.name={}", request.name),
        format!("user.metaservice.kind={}", if request.kind == Kind::Vm { "vm" } else { "container" }), format!("user.metaservice.cpu={}", request.cpu),
        format!("user.metaservice.ram_mb={}", request.ram_mb), format!("user.metaservice.disk_gb={}", request.disk_gb),
        format!("user.metaservice.gpu_mode={}", match request.gpu_mode { GpuMode::None => "none", GpuMode::Container => "container", GpuMode::Passthrough => "passthrough" }),
    ];
    for setting in settings.into_iter().chain(cpu_settings(request)) {
        list.push("-c".into());
        list.push(setting);
    }
    list.push("-d".into());
    list.push(format!("root,size={}GiB", request.disk_gb));
    list
}

/// The sockets of a VM that asked for more than one. One socket is the engine's own layout, as before.
fn sockets_asked(request: &CreateRequest) -> Option<u32> {
    request.cpu_sockets.filter(|sockets| *sockets > 1)
}

/// The CPU model of a VM that asked for one other than `host`, the machine's own CPU (as before).
fn model_asked(request: &CreateRequest) -> Option<&str> {
    request.cpu_type.as_deref().filter(|model| *model != HOST_MODEL)
}

/// The value of `limits.cpu`: the number of CPUs, or for a VM spread over S sockets `sockets=S,cores=C,threads=1` with C = cpu / S.
/// Incus reads a part that is left out as 1; threads=1 is written anyway, so the setting says the whole layout.
fn cpu_limit(request: &CreateRequest) -> String {
    match sockets_asked(request) {
        Some(sockets) => format!("sockets={sockets},cores={},threads=1", request.cpu / sockets),
        None => request.cpu.to_string(),
    }
}

/// A container's CPU cap and the record of each CPU setting that changes anything. Nothing when nothing does.
fn cpu_settings(request: &CreateRequest) -> Vec<String> {
    let mut settings = Vec::new();
    if let Some(percent) = request.cpu_limit_percent { settings.push(format!("limits.cpu.allowance={percent}ms/{CPU_PERIOD_MS}ms")); }
    if let Some(sockets) = sockets_asked(request) { settings.push(format!("{CPU_SOCKETS_KEY}={sockets}")); }
    if let Some(model) = model_asked(request) { settings.push(format!("{CPU_TYPE_KEY}={model}")); }
    if !request.cpu_flags.is_empty() { settings.push(format!("{CPU_FLAGS_KEY}={}", flags_record(&request.cpu_flags))); }
    if let Some(percent) = request.cpu_limit_percent { settings.push(format!("{CPU_LIMIT_KEY}={percent}")); }
    settings
}

/// The flags as asked, like `nested-virt=on,aes=off`.
fn flags_record(flags: &[(CpuFlag, bool)]) -> String {
    flags.iter().map(|(flag, on)| format!("{}={}", flag.name(), if *on { "on" } else { "off" })).collect::<Vec<_>>().join(",")
}

/// The `raw.qemu` setting of a VM that asked for a CPU model or flags (the model is `host` when only flags were asked), else nothing.
/// Incus puts raw.qemu after its own `-cpu host,...` and QEMU keeps the last `-cpu`, so this replaces the extras Incus gives `host` too
/// (hv_passthrough, +invtsc and the like). The model is one the machine offers and the flags are fixed words, so nothing typed reaches QEMU;
/// incus runs without a shell, so `-cpu` and its value travel in one argument. `vendor` says what nested-virt is: svm on AMD, vmx on Intel.
pub fn cpu_model_arguments(request: &CreateRequest, vendor: Option<CpuVendor>) -> Vec<String> {
    if request.kind != Kind::Vm || (model_asked(request).is_none() && request.cpu_flags.is_empty()) {
        return Vec::new();
    }
    let model = model_asked(request).unwrap_or(HOST_MODEL);
    let words: Vec<&str> = std::iter::once(model).chain(request.cpu_flags.iter().filter_map(|(flag, on)| qemu_flag(*flag, *on, vendor))).collect();
    args(&["-c", &format!("raw.qemu=-cpu {}", words.join(","))])
}

/// QEMU's words for one flag. Off takes both svm and vmx away. Switching nested-virt on needs the vendor; without one the create is refused before it gets here.
fn qemu_flag(flag: CpuFlag, on: bool, vendor: Option<CpuVendor>) -> Option<&'static str> {
    match (flag, on, vendor) {
        (CpuFlag::Aes, true, _) => Some("+aes"),
        (CpuFlag::Aes, false, _) => Some("-aes"),
        (CpuFlag::NestedVirt, false, _) => Some("-svm,-vmx"),
        (CpuFlag::NestedVirt, true, Some(CpuVendor::Amd)) => Some("+svm"),
        (CpuFlag::NestedVirt, true, Some(CpuVendor::Intel)) => Some("+vmx"),
        (CpuFlag::NestedVirt, true, None) => None,
    }
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
