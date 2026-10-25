//! What this machine is: cores, memory, disk, GPU. Cores and GPU are measured once at start; RAM and disk are read again (`read_machine`).
use crate::live_space::Reading;
use crate::models::{Gpu, Specs};
use sysinfo::{Disks, MemoryRefreshKind, RefreshKind, System};

const BYTES_PER_MB: u64 = 1024 * 1024;
const BYTES_PER_GB: u64 = 1_000_000_000;

pub fn measure(nvidia_smi: Option<&str>) -> Specs {
    let system = System::new_with_specifics(RefreshKind::new().with_memory(MemoryRefreshKind::new().with_ram()));
    let lscpu = crate::cpu_model::read_lscpu();
    Specs {
        os: std::env::consts::OS.to_string(),
        arch: std::env::consts::ARCH.to_string(),
        cpu_cores: std::thread::available_parallelism().map(|n| n.get() as u32).unwrap_or(1),
        cpu_model: crate::cpu_model::read(lscpu.as_deref()),
        ram_total_mb: system.total_memory() / BYTES_PER_MB,
        disk_total_gb: root_disk().map(|(total, _)| total).unwrap_or(1).max(1),
        gpu: nvidia_smi.map(read_nvidia_smi).unwrap_or_default(),
        hardware: crate::hardware::read(lscpu.as_deref()),
    }
}

/// (total, available) of the volume holding "/" in GB.
fn root_disk() -> Option<(u64, u64)> {
    let disks = Disks::new_with_refreshed_list();
    let root = disks.list().iter().filter(|d| d.mount_point() == std::path::Path::new("/")).max_by_key(|d| d.total_space())
        .or_else(|| disks.list().iter().max_by_key(|d| d.total_space()))?;
    Some((root.total_space() / BYTES_PER_GB, root.available_space() / BYTES_PER_GB))
}

/// A fresh reading of RAM and the root volume: one memory read and one volume listing, no external program.
pub fn read_machine() -> Option<Reading> {
    let system = System::new_with_specifics(RefreshKind::new().with_memory(MemoryRefreshKind::new().with_ram()));
    let (disk_total_gb, disk_available_gb) = root_disk()?;
    Some(Reading { ram_total_mb: system.total_memory() / BYTES_PER_MB, disk_total_gb, disk_available_gb })
}

/// The GPU details asked first. A driver too old to know one of these fields refuses the whole question, so the helper then asks for the name and memory only.
const GPU_DETAILS_QUERY: &str = "--query-gpu=name,memory.total,compute_cap,driver_version,clocks.max.sm,addressing_mode";
const GPU_BASICS_QUERY: &str = "--query-gpu=name,memory.total";
const MAX_GPU_CLOCK_MHZ: u32 = 20_000;

fn read_nvidia_smi(path: &str) -> Vec<Gpu> {
    let ask = |query: &str| {
        let output = std::process::Command::new(path).args([query, "--format=csv,noheader,nounits"]).stdin(std::process::Stdio::null()).output();
        output.ok().filter(|o| o.status.success()).map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
    };
    match ask(GPU_DETAILS_QUERY) {
        Some(text) => parse_nvidia_smi_details(&text),
        None => ask(GPU_BASICS_QUERY).map(|text| parse_nvidia_smi(&text)).unwrap_or_default(),
    }
}

/// Lines like `NVIDIA GB10, 131072` (name, MiB). Memory is optional: some systems report [N/A].
pub fn parse_nvidia_smi(text: &str) -> Vec<Gpu> {
    text.lines().take(16).filter_map(basic_gpu).collect()
}

/// One `name, memory` pair. The name may itself hold a comma, so the memory is the last field.
fn basic_gpu(line: &str) -> Option<Gpu> {
    let (name, memory) = line.rsplit_once(',')?;
    let name = name.trim();
    (!name.is_empty()).then(|| Gpu { vendor: "nvidia".into(), model: name.chars().take(200).collect(), memory_mb: memory.trim().parse().ok(), ..Gpu::default() })
}

/// Lines like `NVIDIA GB10, [N/A], 12.1, 580.173.02, 3003, ATS` (name, MiB, compute capability, driver, top clock in MHz, addressing mode).
/// A detail that is [N/A] or out of shape is left out. A GPU without memory of its own that reaches the machine's memory over ATS uses the system memory.
pub fn parse_nvidia_smi_details(text: &str) -> Vec<Gpu> {
    text.lines().take(16).filter_map(|line| {
        let mut fields = line.rsplitn(5, ',').map(str::trim);
        let (addressing, clock, driver, capability) = (fields.next()?, fields.next()?, fields.next()?, fields.next()?);
        let mut gpu = basic_gpu(fields.next()?)?;
        let capability = Some(capability).filter(|text| is_compute_capability(text));
        gpu.architecture = capability.and_then(architecture).map(String::from);
        gpu.compute_capability = capability.map(String::from);
        gpu.driver_version = Some(driver).filter(|text| is_driver_version(text)).map(String::from);
        gpu.max_clock_mhz = clock.parse().ok().filter(|mhz| (1..=MAX_GPU_CLOCK_MHZ).contains(mhz));
        gpu.uses_system_memory = match (addressing, gpu.memory_mb) {
            (_, Some(_)) => Some(false),
            ("ATS", None) => Some(true),
            _ => None,
        };
        Some(gpu)
    }).collect()
}

/// `12.1`: one or two digits, a dot, one or two digits.
fn is_compute_capability(text: &str) -> bool {
    let digits = |part: &str| (1..=2).contains(&part.len()) && part.bytes().all(|b| b.is_ascii_digit());
    text.split_once('.').is_some_and(|(major, minor)| digits(major) && digits(minor))
}

/// `580.173.02`: a letter or digit, then up to 31 letters, digits, dots or dashes.
fn is_driver_version(text: &str) -> bool {
    let first_ok = text.bytes().next().is_some_and(|b| b.is_ascii_alphanumeric());
    first_ok && text.len() <= 32 && text.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
}

/// The GPU family NVIDIA names for a compute capability (the CUDA programming guide's table); None for one this helper does not know.
pub fn architecture(capability: &str) -> Option<&'static str> {
    let (major, minor) = capability.split_once('.')?;
    let (major, minor): (u32, u32) = (major.parse().ok()?, minor.parse().ok()?);
    Some(match (major, minor) {
        (10..=12, _) => "Blackwell",
        (9, _) => "Hopper",
        (8, 9) => "Ada Lovelace",
        (8, _) => "Ampere",
        (7, 5) => "Turing",
        (7, _) => "Volta",
        (6, _) => "Pascal",
        (5, _) => "Maxwell",
        (3, _) => "Kepler",
        _ => return None,
    })
}

pub fn find_nvidia_smi() -> Option<String> {
    ["/usr/bin/nvidia-smi", "/usr/local/bin/nvidia-smi", "/run/current-system/sw/bin/nvidia-smi"].iter().find(|p| std::path::Path::new(p).is_file()).map(|p| p.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nvidia_smi_lines() {
        let gpus = parse_nvidia_smi("NVIDIA GB10, 131072\nNVIDIA H100 80GB HBM3, 81559\nNVIDIA Thing, [N/A]\n, 5\njunk\n");
        assert_eq!(gpus.iter().map(|g| g.model.as_str()).collect::<Vec<_>>(), ["NVIDIA GB10", "NVIDIA H100 80GB HBM3", "NVIDIA Thing"]);
        assert_eq!((gpus[0].memory_mb, gpus[2].memory_mb), (Some(131072), None));
        assert!(parse_nvidia_smi("").is_empty());
    }

    #[test]
    fn nvidia_smi_details_name_the_family_and_say_when_the_memory_is_the_machines() {
        let gpus = parse_nvidia_smi_details("NVIDIA GB10, [N/A], 12.1, 580.173.02, 3003, ATS\nNVIDIA GeForce RTX 5090, 32607, 12.0, 580.178.04, 3090, HMM\n");
        let spark = &gpus[0];
        assert_eq!((spark.model.as_str(), spark.memory_mb, spark.uses_system_memory), ("NVIDIA GB10", None, Some(true)));
        assert_eq!((spark.architecture.as_deref(), spark.compute_capability.as_deref(), spark.driver_version.as_deref(), spark.max_clock_mhz), (Some("Blackwell"), Some("12.1"), Some("580.173.02"), Some(3003)));
        assert_eq!((gpus[1].memory_mb, gpus[1].uses_system_memory, gpus[1].max_clock_mhz), (Some(32607), Some(false), Some(3090)));
    }

    #[test]
    fn nvidia_smi_details_that_are_missing_or_odd_are_left_out() {
        let gpus = parse_nvidia_smi_details("Odd, Card, [N/A], [N/A], [N/A], 99999, [N/A]\nNVIDIA A100, 40960, 8.0, <b>, 0, None\ntoo, few\n");
        assert_eq!(gpus.len(), 2);
        assert_eq!((gpus[0].model.as_str(), gpus[0].architecture.as_deref(), gpus[0].compute_capability.as_deref(), gpus[0].driver_version.as_deref()), ("Odd, Card", None, None, None));
        assert_eq!((gpus[0].max_clock_mhz, gpus[0].uses_system_memory), (None, None));
        assert_eq!((gpus[1].architecture.as_deref(), gpus[1].driver_version.as_deref(), gpus[1].max_clock_mhz, gpus[1].uses_system_memory), (Some("Ampere"), None, None, Some(false)));
    }

    #[test]
    fn each_compute_capability_names_its_family() {
        for (capability, family) in [("12.1", "Blackwell"), ("10.0", "Blackwell"), ("9.0", "Hopper"), ("8.9", "Ada Lovelace"), ("8.6", "Ampere"), ("7.5", "Turing"), ("7.0", "Volta"), ("6.1", "Pascal")] {
            assert_eq!(architecture(capability), Some(family), "{capability}");
        }
        assert_eq!(architecture("13.0"), None);
        assert_eq!(architecture("x"), None);
    }

    #[test]
    fn the_gpu_details_read_as_the_contract_spells_them() {
        let gpu = &parse_nvidia_smi_details("NVIDIA GB10, [N/A], 12.1, 580.173.02, 3003, ATS\n")[0];
        let json = serde_json::to_value(gpu).unwrap();
        assert_eq!(json, serde_json::json!({"vendor": "nvidia", "model": "NVIDIA GB10", "architecture": "Blackwell", "compute_capability": "12.1", "driver_version": "580.173.02", "max_clock_mhz": 3003, "uses_system_memory": true}));
        assert_eq!(serde_json::to_value(&parse_nvidia_smi("NVIDIA T4, 15360\n")[0]).unwrap(), serde_json::json!({"vendor": "nvidia", "model": "NVIDIA T4", "memory_mb": 15360}));
    }

    #[test]
    fn this_machine_has_sane_numbers() {
        let specs = measure(None);
        assert!(specs.cpu_cores >= 1 && specs.ram_total_mb >= 256 && specs.disk_total_gb >= 1);
        assert!(["linux", "macos"].contains(&specs.os.as_str()));
    }
}
