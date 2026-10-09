//! What this machine is: cores, memory, disk, GPU. Measured once at start (the disk is asked again each time).
use crate::models::{Gpu, Specs};
use sysinfo::{Disks, MemoryRefreshKind, RefreshKind, System};

const BYTES_PER_MB: u64 = 1024 * 1024;
const BYTES_PER_GB: u64 = 1_000_000_000;

pub fn measure(nvidia_smi: Option<&str>) -> Specs {
    let system = System::new_with_specifics(RefreshKind::new().with_memory(MemoryRefreshKind::new().with_ram()));
    Specs {
        os: std::env::consts::OS.to_string(),
        arch: std::env::consts::ARCH.to_string(),
        cpu_cores: std::thread::available_parallelism().map(|n| n.get() as u32).unwrap_or(1),
        ram_total_mb: system.total_memory() / BYTES_PER_MB,
        disk_total_gb: root_disk().map(|(total, _)| total).unwrap_or(1).max(1),
        gpu: nvidia_smi.map(read_nvidia_smi).unwrap_or_default(),
    }
}

/// (total, available) of the volume holding "/" in GB.
fn root_disk() -> Option<(u64, u64)> {
    let disks = Disks::new_with_refreshed_list();
    let root = disks.list().iter().filter(|d| d.mount_point() == std::path::Path::new("/")).max_by_key(|d| d.total_space())
        .or_else(|| disks.list().iter().max_by_key(|d| d.total_space()))?;
    Some((root.total_space() / BYTES_PER_GB, root.available_space() / BYTES_PER_GB))
}

/// Free space the file system reports, in GB.
pub fn available_disk_gb() -> Option<u64> {
    root_disk().map(|(_, available)| available)
}

fn read_nvidia_smi(path: &str) -> Vec<Gpu> {
    let output = std::process::Command::new(path).args(["--query-gpu=name,memory.total", "--format=csv,noheader,nounits"]).stdin(std::process::Stdio::null()).output();
    output.ok().filter(|o| o.status.success()).map(|o| parse_nvidia_smi(&String::from_utf8_lossy(&o.stdout))).unwrap_or_default()
}

/// Lines like `NVIDIA GB10, 131072` (name, MiB). Memory is optional: some systems report [N/A].
pub fn parse_nvidia_smi(text: &str) -> Vec<Gpu> {
    text.lines().take(16).filter_map(|line| {
        let (name, memory) = line.rsplit_once(',')?;
        let name = name.trim();
        (!name.is_empty()).then(|| Gpu { vendor: "nvidia".into(), model: name.chars().take(200).collect(), memory_mb: memory.trim().parse().ok() })
    }).collect()
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
    fn this_machine_has_sane_numbers() {
        let specs = measure(None);
        assert!(specs.cpu_cores >= 1 && specs.ram_total_mb >= 256 && specs.disk_total_gb >= 1);
        assert!(["linux", "macos"].contains(&specs.os.as_str()));
    }
}
