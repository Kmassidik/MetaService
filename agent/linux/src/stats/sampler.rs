//! Takes one reading of the machine from a /proc tree and compares it with the sample before it, so the answer carries ready percentages.
use super::clock::iso8601;
use super::cpu::{self, CpuTimes};
use super::disks::{self, SizeOf};
use super::model::{Cpu, Network, Process, Stats, MAX_CORES};
use super::network::{self, Counters};
use super::processes::{self, Earlier, Seen};
use super::memory;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
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
    /// None when this sample did not scan the programs: the next one has nothing to compare them with.
    processes: Option<Earlier>,
}

pub struct Sampler {
    environment: Environment,
    previous: Mutex<Option<Sample>>,
}

impl Sampler {
    pub fn new(environment: Environment) -> Self {
        Sampler { environment, previous: Mutex::new(None) }
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
        let seen = with_processes.then(|| processes::scan(&self.environment.root.join("proc")));
        let mut slot = self.previous.lock().map_err(|_| "the sampler lock is broken".to_string())?;
        let before = slot.as_ref().filter(|b| comparable(b, now, &cpu_times));
        let seconds = before.map(|b| now.duration_since(b.at).as_secs_f64());
        let users = processes::parse_passwd(&self.read("etc/passwd").unwrap_or_default()); // no passwd file (a bare container): the user number is shown
        let stats = Stats {
            taken_at: iso8601(unix_seconds),
            measuring: before.is_none(),
            uptime_seconds: uptime(&self.read("proc/uptime")?),
            cpu: Cpu {
                core_count: cpu_times.cores.len().clamp(1, MAX_CORES),
                total_percent: before.map(|b| cpu::percent_between(b.cpu.all, cpu_times.all)),
                cores_percent: before.map(|b| cpu_times.cores.iter().zip(&b.cpu.cores).map(|(now, then)| cpu::percent_between(*then, *now)).collect()),
                load: cpu::parse_load(&self.read("proc/loadavg").unwrap_or_default()), // unreadable: every load value is null
            },
            memory,
            disks: disks::read(&self.read("proc/mounts")?, self.environment.size_of),
            network: Network {
                received_total_bytes: counters.received,
                sent_total_bytes: counters.sent,
                received_bytes_per_second: before.zip(seconds).and_then(|(b, s)| network::rate(b.network.received, counters.received, s)),
                sent_bytes_per_second: before.zip(seconds).and_then(|(b, s)| network::rate(b.network.sent, counters.sent, s)),
            },
            gpus: None,
            processes: self.listed(seen.as_deref(), before, seconds, &users),
        };
        *slot = Some(Sample { at: now, cpu: cpu_times, network: counters, processes: seen.as_deref().map(processes::ticks_of) });
        Ok(stats)
    }
}

impl Sampler {
    /// The top programs, empty when they were not scanned. Their CPU is unknown (null) when there is no earlier list of programs to compare with.
    fn listed(&self, seen: Option<&[Seen]>, before: Option<&Sample>, seconds: Option<f64>, users: &HashMap<u32, String>) -> Vec<Process> {
        let Some(seen) = seen else { return Vec::new() };
        let earlier = before.and_then(|b| b.processes.as_ref());
        processes::top(seen.to_vec(), earlier, seconds.unwrap_or(1.0), self.environment.ticks_per_second as f64, users)
    }
}

fn comparable(before: &Sample, now: Instant, cpu_now: &CpuTimes) -> bool {
    let age = now.saturating_duration_since(before.at);
    age >= MIN_SAMPLE_GAP && age <= MAX_SAMPLE_AGE && before.cpu.cores.len() == cpu_now.cores.len()
}

fn uptime(text: &str) -> u64 {
    text.split_whitespace().next().and_then(|n| n.parse::<f64>().ok()).filter(|v| v.is_finite() && *v >= 0.0).map(|v| v as u64).unwrap_or(0)
}
