//! Takes one reading of the machine from a /proc tree and compares it with the sample before it, so the answer carries ready percentages.
use super::clock::iso8601;
use super::cpu::{self, CpuTimes};
use super::disks::{self, SizeOf};
use super::diskio;
use super::model::{Cpu, DiskIo, Network, Process, Stats, MAX_CORES};
use super::network::{self, Counters};
use super::processes::{self, Earlier, Seen};
use super::topology::{self, Topology};
use super::{memory, thermal};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

/// A sample older than this is not compared with: the answer says "measuring" instead of averaging over a long gap.
pub const MAX_SAMPLE_AGE: Duration = Duration::from_secs(60);
const MIN_SAMPLE_GAP: Duration = Duration::from_millis(10);

/// Where to read and how: the root of the /proc tree (a test points it at a fake one), the size function, the kernel's clock tick rate.
pub struct Environment {
    pub root: PathBuf,
    pub size_of: SizeOf,
    pub ticks_per_second: u64,
}

struct Sample {
    at: Instant,
    cpu: CpuTimes,
    network: Counters,
    disk: Option<diskio::Counters>,
    /// None when this sample did not scan the programs: the next one has nothing to compare them with.
    processes: Option<Earlier>,
}

pub struct Sampler {
    environment: Environment,
    previous: Mutex<Option<Sample>>,
    /// The CPU layout does not change while the helper runs: read once.
    topology: OnceLock<Topology>,
}

impl Sampler {
    pub fn new(environment: Environment) -> Self {
        Sampler { environment, previous: Mutex::new(None), topology: OnceLock::new() }
    }

    fn read(&self, relative: &str) -> Result<String, String> {
        let path = self.environment.root.join(relative);
        std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {e}", path.display()))
    }

    /// `now` times the gap between samples; `unix_seconds` is the wall clock written into the answer. `with_processes` false: /proc/<pid> is not walked and the list is empty.
    pub fn take(&self, now: Instant, unix_seconds: u64, with_processes: bool) -> Result<Stats, String> {
        let cpu_times = cpu::parse_times(&self.read("proc/stat")?).ok_or("proc/stat has no cpu line")?;
        let memory = memory::parse(&self.read("proc/meminfo")?).ok_or("proc/meminfo has no MemTotal")?;
        let counters = network::parse(&self.read("proc/net/dev")?);
        let disk_counters = self.read("proc/diskstats").ok().and_then(|text| diskio::parse(&text, &self.environment.root));
        let seen = with_processes.then(|| processes::scan(&self.environment.root.join("proc")));
        let mut slot = self.previous.lock().map_err(|_| "the sampler lock is broken".to_string())?;
        let before = slot.as_ref().filter(|b| comparable(b, now, &cpu_times));
        let seconds = before.map(|b| now.duration_since(b.at).as_secs_f64());
        let users = processes::parse_passwd(&self.read("etc/passwd").unwrap_or_default()); // no passwd file (a bare container): the user number is shown
        let stats = Stats {
            taken_at: iso8601(unix_seconds),
            measuring: before.is_none(),
            uptime_seconds: uptime(&self.read("proc/uptime")?),
            cpu: self.cpu_section(&cpu_times, before),
            memory,
            disks: disks::read(&self.read("proc/mounts")?, self.environment.size_of),
            network: network_section(&counters, before, seconds),
            disk_io: disk_io(disk_counters, before, seconds),
            process_count: processes::count(&self.environment.root.join("proc")),
            gpus: None,
            processes: self.listed(seen.as_deref(), before, seconds, &users),
        };
        *slot = Some(Sample { at: now, cpu: cpu_times, network: counters, disk: disk_counters, processes: seen.as_deref().map(processes::ticks_of) });
        Ok(stats)
    }

    fn cpu_section(&self, now: &CpuTimes, before: Option<&Sample>) -> Cpu {
        let layout = self.topology.get_or_init(|| topology::read(&self.environment.root, &now.ids));
        let grouped = layout.core_of.len() == now.cores.len(); // a CPU came or went since the first reading: no grouping
        Cpu {
            core_count: now.cores.len().clamp(1, MAX_CORES),
            total_percent: before.map(|b| cpu::percent_between(b.cpu.all, now.all)),
            cores_percent: before.map(|b| now.cores.iter().zip(&b.cpu.cores).map(|(now, then)| cpu::percent_between(*then, *now)).collect()),
            load: cpu::parse_load(&self.read("proc/loadavg").unwrap_or_default()), // unreadable: every load value is null
            physical_cores: grouped.then_some(layout.physical_cores),
            core_of: grouped.then(|| layout.core_of.clone()),
            breakdown: before.and_then(|b| cpu::breakdown_between(&b.cpu.fields, &now.fields)),
            frequency_mhz: thermal::frequency(&self.environment.root, &now.ids),
            temperature_celsius: thermal::temperature(&self.environment.root),
        }
    }

    /// The top programs, empty when they were not scanned. Their CPU is unknown (null) when there is no earlier list of programs to compare with.
    fn listed(&self, seen: Option<&[Seen]>, before: Option<&Sample>, seconds: Option<f64>, users: &HashMap<u32, String>) -> Vec<Process> {
        let Some(seen) = seen else { return Vec::new() };
        let earlier = before.and_then(|b| b.processes.as_ref());
        processes::top(seen.to_vec(), earlier, seconds.unwrap_or(1.0), self.environment.ticks_per_second as f64, users)
    }
}

fn network_section(counters: &Counters, before: Option<&Sample>, seconds: Option<f64>) -> Network {
    let rate_of = |pick: fn(&Counters) -> u64| before.zip(seconds).and_then(|(b, s)| network::rate(pick(&b.network), pick(counters), s));
    Network {
        received_total_bytes: counters.received,
        sent_total_bytes: counters.sent,
        received_bytes_per_second: rate_of(|c| c.received),
        sent_bytes_per_second: rate_of(|c| c.sent),
        errors_in_total: counters.errors_in,
        errors_out_total: counters.errors_out,
        drops_in_total: counters.drops_in,
        drops_out_total: counters.drops_out,
    }
}

/// Both speeds, or nothing: no disks, nothing to compare with, or a counter that went back.
fn disk_io(now: Option<diskio::Counters>, before: Option<&Sample>, seconds: Option<f64>) -> Option<DiskIo> {
    let (now, then, seconds) = (now?, before?.disk?, seconds?);
    Some(DiskIo {
        read_bytes_per_second: network::rate(then.read_bytes, now.read_bytes, seconds)?,
        write_bytes_per_second: network::rate(then.written_bytes, now.written_bytes, seconds)?,
    })
}

fn comparable(before: &Sample, now: Instant, cpu_now: &CpuTimes) -> bool {
    let age = now.saturating_duration_since(before.at);
    age >= MIN_SAMPLE_GAP && age <= MAX_SAMPLE_AGE && before.cpu.cores.len() == cpu_now.cores.len()
}

fn uptime(text: &str) -> u64 {
    text.split_whitespace().next().and_then(|n| n.parse::<f64>().ok()).filter(|v| v.is_finite() && *v >= 0.0).map(|v| v as u64).unwrap_or(0)
}
