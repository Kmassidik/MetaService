//! `GET /v1/storage` and `POST /v1/storage/scan`: a map of what fills this machine's disk, for the panel's Storage tab (drawn like disktree).
//! A scan walks `/` in one background thread at the lowest CPU and disk priority, never leaving the root file system, and keeps the
//! last finished map in memory. Read only: nothing here writes, moves or deletes a file.
mod flat;
mod kinds;
#[cfg(test)]
mod tests;
mod walk;

use crate::stats::iso8601;
use serde::{Serialize, Serializer};
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use walk::{Counters, Settings};

/// A new scan is not started sooner than this after the last one ended.
pub const COOLDOWN: Duration = Duration::from_secs(30);
/// The floor is the used space split this many ways: at most this many entries per level can be big enough to keep.
const TILES_PER_LEVEL: u64 = 4_000;
const MIN_FLOOR_BYTES: u64 = 1024 * 1024;
const KEEP_DEPTH: usize = 24;
const MAX_ERROR_CHARS: usize = 300;
const LOWEST_NICE: libc::c_int = 19;

#[derive(Debug, Serialize)]
pub struct Disk {
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub free_bytes: u64,
}

#[derive(Debug, Serialize)]
pub struct Map {
    pub root: String,
    pub finished_at: String,
    pub seconds: f64,
    pub entries: u64,
    pub unreadable: u64,
    pub disk: Disk,
    pub nodes: Vec<flat::Node>,
}

#[derive(Debug, Serialize)]
pub struct Progress {
    pub entries: u64,
    pub bytes: u64,
}

/// What the routes answer: whether a scan runs (and how far it is), why the last one failed, and the last finished map.
pub struct Answer {
    pub scanning: bool,
    pub progress: Option<Progress>,
    pub error: Option<String>,
    pub map: Option<Arc<Map>>,
}

impl Serialize for Answer {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        #[derive(Serialize)]
        struct Wire<'a> {
            scanning: bool,
            progress: Option<&'a Progress>,
            error: Option<&'a str>,
            map: Option<&'a Map>,
        }
        Wire { scanning: self.scanning, progress: self.progress.as_ref(), error: self.error.as_deref(), map: self.map.as_deref() }.serialize(serializer)
    }
}

#[derive(Default)]
struct State {
    scanning: bool,
    ended: Option<Instant>,
    error: Option<String>,
    map: Option<Arc<Map>>,
}

pub struct Storage {
    root: PathBuf,
    state: Arc<Mutex<State>>,
    counters: Arc<Counters>,
}

impl Storage {
    pub fn system() -> Storage {
        Storage::at(PathBuf::from("/"))
    }

    pub fn at(root: PathBuf) -> Storage {
        Storage { root, state: Default::default(), counters: Default::default() }
    }

    pub fn answer(&self) -> Answer {
        let state = self.state.lock().unwrap();
        let progress = state.scanning.then(|| Progress { entries: self.counters.entries.load(Ordering::Relaxed), bytes: self.counters.bytes.load(Ordering::Relaxed) });
        Answer { scanning: state.scanning, progress, error: state.error.clone(), map: state.map.clone() }
    }

    /// Starts a scan unless one runs or the last one ended less than `COOLDOWN` ago, then answers like `answer`.
    pub fn scan(&self) -> Answer {
        {
            let mut state = self.state.lock().unwrap();
            let rested = state.ended.is_none_or(|ended| ended.elapsed() >= COOLDOWN);
            if !state.scanning && rested {
                state.scanning = true;
                self.counters.reset();
                let (root, shared, counters) = (self.root.clone(), self.state.clone(), self.counters.clone());
                let started = std::thread::Builder::new().name("storage-scan".into()).spawn(move || {
                    lower_priority();
                    let outcome = scan_once(&root, &counters);
                    let mut state = shared.lock().unwrap();
                    state.scanning = false;
                    state.ended = Some(Instant::now());
                    match outcome {
                        Ok(map) => {
                            state.map = Some(Arc::new(map));
                            state.error = None;
                        }
                        Err(cause) => {
                            eprintln!("storage scan failed: {cause}");
                            state.error = Some(cause.chars().take(MAX_ERROR_CHARS).collect());
                        }
                    }
                });
                if let Err(cause) = started {
                    eprintln!("storage scan could not start: {cause}");
                    state.scanning = false;
                }
            }
        }
        self.answer()
    }

    #[cfg(test)]
    fn wait(&self) {
        while self.state.lock().unwrap().scanning {
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}

fn scan_once(root: &Path, counters: &Counters) -> Result<Map, String> {
    let started = Instant::now();
    let before = crate::stats::disk_sizes(root).ok_or("the size of the disk could not be read")?;
    let used = before.total.saturating_sub(before.free);
    let mountinfo = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let settings = Settings { floor: (used / TILES_PER_LEVEL).max(MIN_FLOOR_BYTES), keep_depth: KEEP_DEPTH, skip: walk::other_mounts(&mountinfo, root) };
    let walked = walk::walk(root, &settings, counters).map_err(|cause| format!("the disk could not be read: {cause}"))?;
    let mut tree = walked.root;
    kinds::classify(&mut tree);
    flat::fit(&mut tree, flat::MAX_NODES);
    let after = crate::stats::disk_sizes(root).unwrap_or(before);
    let free = after.free.min(after.total);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|cause| cause.to_string())?.as_secs();
    Ok(Map {
        root: root.to_string_lossy().into_owned(),
        finished_at: iso8601(now),
        seconds: (started.elapsed().as_secs_f64() * 10.0).round() / 10.0,
        entries: walked.entries,
        unreadable: walked.unreadable,
        disk: Disk { total_bytes: after.total, used_bytes: after.total - free, free_bytes: free },
        nodes: flat::flatten(&tree),
    })
}

/// The scan should never slow the machine's VMs: lowest CPU priority and the idle disk class, for this thread only.
fn lower_priority() {
    // SAFETY: gettid takes nothing and cannot fail.
    let thread = unsafe { libc::syscall(libc::SYS_gettid) };
    const IOPRIO_WHO_PROCESS: libc::c_long = 1;
    const IOPRIO_CLASS_IDLE: libc::c_long = 3;
    const IOPRIO_CLASS_SHIFT: libc::c_long = 13;
    // SAFETY: both calls only change this thread's own priorities; a failure leaves them as they were.
    unsafe {
        libc::setpriority(libc::PRIO_PROCESS, thread as libc::id_t, LOWEST_NICE);
        libc::syscall(libc::SYS_ioprio_set, IOPRIO_WHO_PROCESS, thread, IOPRIO_CLASS_IDLE << IOPRIO_CLASS_SHIFT);
    }
}
