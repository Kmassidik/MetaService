//! The only things the runner asks of the machine: run a step, start a program that keeps running, and kill one.
//!
//! [`RealHost`] is the machine: it never uses a shell, so a step is a program and its argv, and nothing a caller sent is ever parsed as a command line.
//! Every step it runs comes from the builders in `sandbox::firecracker`, which take a validated id and two numbers and nothing else.
//!
//! [`RealHost`] keeps the children it started, so it can reap them, and it also writes their pids down: a runner that restarted still has to be able to
//! stop a sandbox it no longer remembers starting.
use crate::sandbox::firecracker::Step;
use crate::sandbox::runner::layout::Files;
use std::collections::HashMap;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

/// What the runner needs from the machine. The tests give it a host that records instead of doing anything.
pub trait Host: Send + Sync {
    /// Runs one step to the end and answers the first line it complained with when it did not succeed.
    fn run(&self, step: &Step) -> Result<(), String>;
    /// Starts a step that keeps running after this returns, and answers the id this runner will use to stop it.
    fn spawn(&self, files: &Files, step: &Step) -> Result<(), String>;
    /// Stops what `spawn` started. A sandbox that is not running is not an error: a stop is repeated freely.
    fn stop(&self, files: &Files) -> Result<(), String>;
}

/// The machine itself, as root: programs straight out of the builders, and pids kept both in memory and on disk.
#[derive(Default)]
pub struct RealHost {
    children: Mutex<HashMap<String, Child>>,
}

impl Host for RealHost {
    fn run(&self, step: &Step) -> Result<(), String> {
        let output = Command::new(step.program).args(&step.arguments).stdin(Stdio::null()).output().map_err(|e| format!("{}: {e}", step.program))?;
        if output.status.success() {
            return Ok(());
        }
        Err(first_line(&output.stderr).unwrap_or_else(|| format!("{} failed with {}", step.program, output.status)))
    }

    /// The jailer execs Firecracker in the process it forks, so the child's pid is Firecracker's own: it is kept on disk for a runner that restarts. Its
    /// console goes to the sandbox's own file, because a guest that does not boot has nothing else to say.
    fn spawn(&self, files: &Files, step: &Step) -> Result<(), String> {
        let console = std::fs::File::create(&files.console).map_err(|e| format!("cannot make the sandbox's console file: {e}"))?;
        let child = Command::new(step.program)
            .args(&step.arguments)
            .stdin(Stdio::null())
            .stdout(console)
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("{}: {e}", step.program))?;
        std::fs::write(&files.pid, child.id().to_string()).map_err(|e| format!("cannot keep the sandbox's pid: {e}"))?;
        self.children.lock().unwrap().insert(files.pid.to_string_lossy().into_owned(), child);
        Ok(())
    }

    fn stop(&self, files: &Files) -> Result<(), String> {
        let key = files.pid.to_string_lossy().into_owned();
        let remembered = self.children.lock().unwrap().remove(&key);
        if let Some(mut child) = remembered {
            let _ = child.kill();
            let _ = child.wait();
            let _ = std::fs::remove_file(&files.pid);
            return Ok(());
        }
        let Ok(text) = std::fs::read_to_string(&files.pid) else { return Ok(()) };
        let pid = text.trim().parse::<i32>().ok().filter(|pid| *pid > 1);
        let Some(pid) = pid else {
            let _ = std::fs::remove_file(&files.pid);
            return Ok(());
        };
        // SAFETY: `kill(2)` only reads its two arguments; a pid this runner wrote down itself, with a signal number from the constant below. A pid
        // that is gone makes the call fail, which is exactly the answer a repeated stop wants.
        let killed = unsafe { libc::kill(pid, libc::SIGKILL) };
        let _ = std::fs::remove_file(&files.pid);
        if killed != 0 {
            return Err(format!("cannot stop the sandbox's process {pid}"));
        }
        Ok(())
    }
}

/// The first line of a program's complaint: enough to log, short enough to keep.
fn first_line(output: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(output);
    let line = text.lines().find(|line| !line.trim().is_empty())?;
    Some(line.chars().take(200).collect())
}
