//! The JSON of `GET /v1/stats` (docs/monitor-contract.md). A value that cannot be known yet is None (null), never 0.
use serde::Serialize;

pub const MAX_PROCESSES: usize = 15;
pub const MAX_DISKS: usize = 16;
pub const MAX_GPUS: usize = 16;
pub const MAX_CORES: usize = 1024;
pub const MAX_NAME_CHARS: usize = 64;
pub const MAX_MOUNT_CHARS: usize = 128;
pub const MAX_FS_CHARS: usize = 32;

/// Text from the machine, cut at `limit` characters (not bytes).
pub fn cut(text: &str, limit: usize) -> String {
    text.chars().take(limit).collect()
}

/// One decimal, as the contract promises.
pub fn one_decimal(value: f64) -> f64 {
    (value * 10.0).round() / 10.0
}

#[derive(Debug, Serialize)]
pub struct Stats {
    pub taken_at: String,
    pub measuring: bool,
    pub uptime_seconds: u64,
    pub cpu: Cpu,
    pub memory: Memory,
    pub disks: Vec<Disk>,
    pub network: Network,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub disk_io: Option<DiskIo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gpus: Option<Vec<GpuStats>>,
    pub processes: Vec<Process>,
}

#[derive(Debug, Serialize)]
pub struct Cpu {
    pub core_count: usize,
    pub total_percent: Option<f64>,
    pub cores_percent: Option<Vec<f64>>,
    pub load: Load,
    /// Physical cores (the logical count is `core_count`). Left out when unknown.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub physical_cores: Option<usize>,
    /// For each logical CPU (same order as `cores_percent`), the index of the physical core it belongs to.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub core_of: Option<Vec<usize>>,
    /// Share of the last interval spent in each state, in percent. Null while measuring.
    pub breakdown: Option<CpuBreakdown>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency_mhz: Option<Frequency>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature_celsius: Option<f64>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct CpuBreakdown {
    pub user: f64,
    pub nice: f64,
    pub system: f64,
    pub idle: f64,
    pub iowait: f64,
    pub irq: f64,
    pub softirq: f64,
    pub steal: f64,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct Frequency {
    pub average: f64,
    pub max: f64,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct DiskIo {
    pub read_bytes_per_second: f64,
    pub write_bytes_per_second: f64,
}

#[derive(Debug, Serialize, Default, PartialEq)]
pub struct Load {
    pub one: Option<f64>,
    pub five: Option<f64>,
    pub fifteen: Option<f64>,
}

#[derive(Debug, Serialize, Default, PartialEq)]
pub struct Memory {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub cached_bytes: u64,
    pub free_bytes: u64,
    pub swap_total_bytes: u64,
    pub swap_used_bytes: u64,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct Disk {
    pub mount: String,
    pub name: String,
    pub fs: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
}

#[derive(Debug, Serialize)]
pub struct Network {
    pub received_total_bytes: u64,
    pub sent_total_bytes: u64,
    pub received_bytes_per_second: Option<f64>,
    pub sent_bytes_per_second: Option<f64>,
    pub errors_in_total: u64,
    pub errors_out_total: u64,
    pub drops_in_total: u64,
    pub drops_out_total: u64,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct GpuStats {
    pub name: String,
    pub utilization_percent: Option<f64>,
    pub memory_used_bytes: Option<u64>,
    pub memory_total_bytes: Option<u64>,
    pub temperature_celsius: Option<f64>,
}

#[derive(Debug, Serialize, Clone, PartialEq)]
pub struct Process {
    pub pid: u32,
    pub name: String,
    pub user: String,
    pub cpu_percent: Option<f64>,
    pub memory_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub threads: Option<u32>,
}
