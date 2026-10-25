//! `GET /v1/stats`: the machine's real state now. Read only. Rules: docs/monitor-contract.md.
mod clock;
mod cpu;
mod diskio;
mod disks;
mod gpu;
mod memory;
mod model;
mod network;
mod processes;
mod request;
mod sampler;
#[cfg(test)]
mod tests;
mod thermal;
mod topology;

use sampler::{Environment, Sampler};
use std::path::PathBuf;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

pub use clock::iso8601;
pub use disks::system_sizes as disk_sizes;
pub use gpu::{query_pid_memory, PidMemory};
pub use model::Stats;
pub use request::wants_processes;

/// Holds the sampler (it remembers the last sample so percentages are ready) and the place of `nvidia-smi`, found once.
pub struct Monitor {
    sampler: Sampler,
    root: PathBuf,
    nvidia_smi: Option<String>,
}

impl Monitor {
    pub fn system(nvidia_smi: Option<String>) -> Self {
        let environment = Environment { root: PathBuf::from("/"), size_of: disks::system_sizes, ticks_per_second: clock_ticks_per_second() };
        let root = environment.root.clone();
        Monitor { sampler: Sampler::new(environment), root, nvidia_smi }
    }

    /// Blocking: reads files and may run `nvidia-smi` for up to three seconds in all. Call it off the async threads.
    /// `with_processes` false skips the walk through /proc/<pid> (the costly part); the list in the answer is then empty.
    pub fn read(&self, with_processes: bool) -> Result<Stats, String> {
        let unix_seconds = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e| e.to_string())?.as_secs();
        let mut stats = self.sampler.take(Instant::now(), unix_seconds, with_processes)?;
        stats.gpus = gpu::read(&self.root, self.nvidia_smi.as_deref(), gpu::QUERY_TIMEOUT);
        Ok(stats)
    }
}

fn clock_ticks_per_second() -> u64 {
    // SAFETY: sysconf with a valid name only reads a constant.
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    u64::try_from(ticks).ok().filter(|t| *t > 0).unwrap_or(100)
}
