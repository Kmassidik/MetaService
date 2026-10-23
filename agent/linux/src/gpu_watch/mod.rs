//! The GPU memory watchdog. A GeForce card has no hardware partitions, so a container's GPU memory limit is kept by watching:
//! every few seconds the programs on the card are read, tied to their containers, and a container that stays over its limit is stopped.
mod cgroup;
mod tracker;
#[cfg(test)]
mod tests;

use crate::incus::{self, Runner, GPU_STOP_CODE_KEY, GPU_STOP_USED_KEY};
use crate::models::{GPU_OVER_LIMIT_CODE, State, Workload};
use crate::stats::PidMemory;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tracker::{Limits, Stop, Tracker, Usage};

/// Seconds between two looks at the card.
pub const WATCH_SECONDS: u64 = 5;
/// Seconds a container gets to stop by itself before it is forced.
pub const STOP_GRACE_SECONDS: &str = "10";
const MIB_PER_GB: u64 = 1024;
const LIST_TIMEOUT: Duration = Duration::from_secs(30);
const STOP_TIMEOUT: Duration = Duration::from_secs(90);
const CONFIG_TIMEOUT: Duration = Duration::from_secs(30);
const SMI_TIMEOUT: Duration = Duration::from_secs(3);

/// Reads the programs on the card with their process ids; None when the card could not be read.
pub type ProgramReader = Box<dyn Fn() -> Option<Vec<PidMemory>> + Send>;
/// Reads the text of `/proc/<pid>/cgroup`; None when the process is gone.
pub type CgroupReader = Box<dyn Fn(u32) -> Option<String> + Send>;

pub struct Watchdog {
    runner: Arc<dyn Runner>,
    read_programs: ProgramReader,
    read_cgroup: CgroupReader,
    tracker: Tracker,
}

impl Watchdog {
    pub fn new(runner: Arc<dyn Runner>, read_programs: ProgramReader, read_cgroup: CgroupReader) -> Self {
        Watchdog { runner, read_programs, read_cgroup, tracker: Tracker::default() }
    }

    /// One look: who has a limit, how much each holds, and the stops that follow. Returns the instances stopped.
    pub fn round(&mut self) -> Vec<String> {
        let limits = match self.limits() {
            Ok(limits) => limits,
            Err(message) => { eprintln!("metaservice-agent: gpu watch: {message}"); return Vec::new(); }
        };
        let usage = if limits.is_empty() { Some(Usage::new()) } else { (self.read_programs)().map(|programs| self.usage_by_container(&programs)) };
        self.tracker.observe(&limits, usage.as_ref()).into_iter().filter_map(|stop| self.stop(stop)).collect()
    }

    /// The running containers that have a limit, in MiB, by instance name.
    fn limits(&self) -> Result<Limits, String> {
        let text = self.runner.run(&["list".to_string(), "--format".into(), "json".into()], LIST_TIMEOUT).map_err(|error| format!("cannot list: {error:?}"))?;
        Ok(incus::parse_list(&text).iter().filter_map(limit_of).collect())
    }

    fn usage_by_container(&self, programs: &[PidMemory]) -> Usage {
        let mut usage: HashMap<String, u64> = HashMap::new();
        for program in programs {
            let Some(name) = (self.read_cgroup)(program.pid).and_then(|text| cgroup::instance_name(&text)) else { continue };
            *usage.entry(name).or_insert(0) += program.used_mib;
        }
        usage
    }

    /// Stops politely, then by force, and records why. Returns the instance when it is stopped.
    fn stop(&mut self, stop: Stop) -> Option<String> {
        let polite = ["stop".to_string(), stop.instance.clone(), "--timeout".into(), STOP_GRACE_SECONDS.into()];
        let forced = ["stop".to_string(), stop.instance.clone(), "--force".into()];
        if self.runner.run(&polite, STOP_TIMEOUT).or_else(|_| self.runner.run(&forced, STOP_TIMEOUT)).is_err() {
            eprintln!("metaservice-agent: gpu watch: could not stop {}", stop.instance);
            self.tracker.stop_failed(&stop.instance);
            return None;
        }
        self.record(&stop);
        Some(stop.instance)
    }

    /// Writes the reason on the instance, so it is still known after the Agent restarts.
    fn record(&self, stop: &Stop) {
        let settings = [(GPU_STOP_CODE_KEY, GPU_OVER_LIMIT_CODE.to_string()), (GPU_STOP_USED_KEY, stop.used_mib.to_string())];
        for (key, value) in settings {
            let call = ["config".to_string(), "set".into(), stop.instance.clone(), key.into(), value];
            if let Err(error) = self.runner.run(&call, CONFIG_TIMEOUT) {
                eprintln!("metaservice-agent: gpu watch: could not record the stop of {}: {error:?}", stop.instance);
            }
        }
    }
}

fn limit_of(workload: &Workload) -> Option<(String, u64)> {
    let limit_gb = workload.gpu_memory_gb.filter(|_| workload.state == State::Running)?;
    Some((incus::name_of(&workload.id), u64::from(limit_gb) * MIB_PER_GB))
}

/// Starts the watchdog on its own thread, reading the card with `nvidia_smi` and the processes from `/proc`.
pub fn spawn(runner: Arc<dyn Runner>, nvidia_smi: String) {
    let read_programs: ProgramReader = Box::new(move || crate::stats::query_pid_memory(&nvidia_smi, SMI_TIMEOUT));
    let read_cgroup: CgroupReader = Box::new(|pid| std::fs::read_to_string(format!("/proc/{pid}/cgroup")).ok());
    let mut watchdog = Watchdog::new(runner, read_programs, read_cgroup);
    std::thread::spawn(move || loop {
        for instance in watchdog.round() {
            eprintln!("metaservice-agent: gpu watch: stopped {instance}, its GPU memory stayed over the limit");
        }
        std::thread::sleep(Duration::from_secs(WATCH_SECONDS));
    });
}
