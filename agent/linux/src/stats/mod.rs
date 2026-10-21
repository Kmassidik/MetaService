//! `GET /v1/stats`: the machine's real state now. Read only. Rules: docs/monitor-contract.md.
mod clock;
mod cpu;
mod disks;
mod gpu;
mod memory;
mod model;
mod network;
mod processes;
mod sampler;
#[cfg(test)]
mod tests;

use sampler::{Environment, Sampler};
use std::path::PathBuf;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

pub use model::Stats;

/// Holds the sampler (it remembers the last sample so percentages are ready) and finds `nvidia-smi` once.
pub struct Monitor {
    sampler: Sampler,
    nvidia_smi: Option<String>,
}

impl Monitor {
    pub fn system(nvidia_smi: Option<String>) -> Self {
        let environment = Environment { root: PathBuf::from("/"), size_of: disks::system_sizes, ticks_per_second: clock_ticks_per_second() };
        Monitor { sampler: Sampler::new(environment), nvidia_smi }
    }

    /// Blocking: reads files and may run `nvidia-smi` for up to three seconds. Call it off the async threads.
    pub fn read(&self) -> Result<Stats, String> {
        let unix_seconds = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|e| e.to_string())?.as_secs();
        let mut stats = self.sampler.take(Instant::now(), unix_seconds)?;
        stats.gpus = self.nvidia_smi.as_deref().and_then(|program| gpu::query(program, gpu::QUERY_TIMEOUT));
        Ok(stats)
    }
}

fn clock_ticks_per_second() -> u64 {
    // SAFETY: sysconf with a valid name only reads a constant.
    let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    u64::try_from(ticks).ok().filter(|t| *t > 0).unwrap_or(100)
}
