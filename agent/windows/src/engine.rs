//! The engine contract, shared with the Linux and Mac helpers. Windows v1 has one implementation:
//! `engine_windows::WindowsEngine`, which refuses every VM action with a plain message.

use crate::models::{Capabilities, Problem, Workload};
pub use crate::models::{EngineError, EngineIdentity};
use crate::ssh_install::InstallReport;
use crate::ssh_keys::{KeyList, Sshd};

/// The program and its arguments a console should run (the Windows engine never returns one for VMs).
pub struct AttachCommand {
    pub program: String,
    pub arguments: Vec<String>,
}
use crate::validate::CreateRequest;

pub trait Engine: Send + Sync {
    fn capabilities(&self) -> Capabilities;
    /// What this engine is, for the facts: a short name and its version, or None when it cannot tell. Never guessed.
    fn identity(&self) -> EngineIdentity;
    /// What on this machine stops it from running workloads right now. Empty means ready.
    fn problems(&self) -> Vec<Problem> {
        Vec::new()
    }
    fn list(&self) -> Result<Vec<Workload>, EngineError>;
    fn create(&self, id: &str, request: &CreateRequest) -> Result<Workload, EngineError>;
    fn set_running(&self, id: &str, running: bool) -> Result<(), EngineError>;
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    fn backup(&self, id: &str) -> Result<String, EngineError>;
    fn delete(&self, id: &str) -> Result<(), EngineError>;
    /// Records which chat bundle version a workload has (None: none, the chat was turned off).
    fn set_bundle_version(&self, id: &str, version: Option<&str>) -> Result<(), EngineError>;
    /// Copies a file from this machine into the workload.
    fn push(&self, id: &str, host_path: &str, container_path: &str) -> Result<(), EngineError>;
    /// Runs one program inside the workload and returns what it printed. Values go in through `environment`, never into the arguments.
    fn exec(&self, id: &str, arguments: &[String], environment: &[(String, String)]) -> Result<String, EngineError>;
    /// Replaces the whole list of SSH public keys that may log in as root of this one workload and says whether sshd is there. The keys go in on standard input, never in arguments.
    fn apply_ssh_keys(&self, id: &str, keys: &KeyList) -> Result<Sshd, EngineError>;
    /// Installs (when missing), locks to keys only, and starts the SSH server inside the workload, with a fixed script and no request data. The keys were written before.
    fn install_sshd(&self, id: &str) -> Result<InstallReport, EngineError>;
    /// (Windows v1 has no app installs: this trait method does not exist.)
    /// What to run on a pty to get an interactive shell inside the workload. The workload must exist; a VM must also answer inside (it has the guest agent),
    /// else this is an error that says so. The command comes only from the engine and the helper's own id, never from a caller.
    fn attach(&self, id: &str) -> Result<AttachCommand, EngineError>;
    /// Like `exec` with no environment, for a quick look inside that must not hang: the engine gives it a short time limit.
    fn quick_exec(&self, id: &str, arguments: &[String]) -> Result<String, EngineError> {
        self.exec(id, arguments, &[])
    }
}

