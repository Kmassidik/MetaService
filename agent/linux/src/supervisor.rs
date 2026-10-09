//! Runs the chat service on this machine as a child of the Agent, and starts it again if it stops. When the Agent stops, so does the chat.
//! The child gets its own process group and the whole group is stopped: the system python3 can be a shim that starts the real python as a grandchild.
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::Duration;

const WATCH_MILLIS: u64 = 300;
const FIRST_DELAY_SECONDS: u64 = 2;
const LONGEST_DELAY_SECONDS: u64 = 30;
const GRACE_TENTHS: u32 = 30;
const MAX_LOG_BYTES: u64 = 1_000_000;

#[derive(Default)]
struct Inner {
    child: Option<Child>,
    generation: u64,
    wanted: bool,
}

pub struct Supervisor {
    python: String,
    log_path: PathBuf,
    inner: Mutex<Inner>,
}

impl Supervisor {
    pub fn new(python: String, log_path: PathBuf) -> Arc<Supervisor> {
        Arc::new(Supervisor { python, log_path, inner: Mutex::new(Inner::default()) })
    }

    /// Start (or restart) the chat service with these arguments.
    pub fn run(self: &Arc<Self>, arguments: Vec<String>) {
        let generation = {
            let mut inner = self.inner.lock().unwrap();
            Self::stop_child(&mut inner);
            inner.generation += 1;
            inner.wanted = true;
            inner.generation
        };
        let this = self.clone();
        std::thread::spawn(move || this.watch(arguments, generation));
    }

    pub fn stop(&self) {
        let mut inner = self.inner.lock().unwrap();
        inner.wanted = false;
        inner.generation += 1;
        Self::stop_child(&mut inner);
    }

    fn current(&self, mine: u64) -> bool {
        let inner = self.inner.lock().unwrap();
        inner.generation == mine && inner.wanted
    }

    /// Keeps one child alive for this generation: starts it, looks every moment whether it is still there, and restarts it after a growing pause.
    fn watch(&self, arguments: Vec<String>, mine: u64) {
        let mut restarts = 0u32;
        while self.current(mine) {
            if self.ensure_running(&arguments, mine) {
                std::thread::sleep(Duration::from_millis(WATCH_MILLIS));
            }
            if self.has_exited(mine) {
                restarts += 1;
                std::thread::sleep(Duration::from_secs(LONGEST_DELAY_SECONDS.min(FIRST_DELAY_SECONDS << restarts.min(4))));
            }
        }
    }

    fn ensure_running(&self, arguments: &[String], mine: u64) -> bool {
        let mut inner = self.inner.lock().unwrap();
        if inner.generation != mine || !inner.wanted {
            return false;
        }
        if inner.child.is_none() {
            inner.child = self.spawn(arguments);
        }
        true
    }

    fn has_exited(&self, mine: u64) -> bool {
        let mut inner = self.inner.lock().unwrap();
        if inner.generation != mine {
            return false;
        }
        let gone = inner.child.as_mut().is_some_and(|child| matches!(child.try_wait(), Ok(Some(_))));
        if gone {
            inner.child = None;
        }
        gone
    }

    fn spawn(&self, arguments: &[String]) -> Option<Child> {
        if std::fs::metadata(&self.log_path).is_ok_and(|m| m.len() > MAX_LOG_BYTES) {
            let _ = std::fs::remove_file(&self.log_path);
        }
        let log = std::fs::OpenOptions::new().create(true).append(true).mode_private(0o600).open(&self.log_path).ok()?;
        let errors = log.try_clone().ok()?;
        Command::new(&self.python).args(arguments).stdin(Stdio::null()).stdout(Stdio::from(log)).stderr(Stdio::from(errors)).process_group(0).spawn().ok()
    }

    fn stop_child(inner: &mut Inner) {
        let Some(mut child) = inner.child.take() else { return };
        let group = -(child.id() as i32);
        unsafe { libc::kill(group, libc::SIGTERM) };
        for _ in 0..GRACE_TENTHS {
            if matches!(child.try_wait(), Ok(Some(_))) {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        unsafe { libc::kill(group, libc::SIGKILL) };
        let _ = child.wait();
    }
}

trait PrivateMode {
    fn mode_private(&mut self, mode: u32) -> &mut Self;
}

impl PrivateMode for std::fs::OpenOptions {
    fn mode_private(&mut self, mode: u32) -> &mut Self {
        std::os::unix::fs::OpenOptionsExt::mode(self, mode)
    }
}
