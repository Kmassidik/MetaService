//! What `autostart` asks of the machine besides files: the user's systemd, the login manager, and whether a process lives. Behind a trait so tests need none of them.
use std::process::Command;

/// What a command answered: whether it exited with 0, and what it printed.
pub struct Reply {
    pub success: bool,
    pub text: String,
}

pub trait Host {
    /// `systemctl --user <arguments>`. Err only when the program cannot be run at all.
    fn systemctl(&self, arguments: &[&str]) -> Result<Reply, String>;
    /// Whether the login keeps its services after logout (`loginctl show-user <user> -p Linger`).
    fn linger(&self, user: &str) -> Result<bool, String>;
    fn process_alive(&self, pid: u32) -> bool;
}

const SYSTEMCTL: &str = "systemctl";
const LOGINCTL: &str = "loginctl";
const LINGER_YES: &str = "Linger=yes";
const RUNTIME_DIR_VARIABLE: &str = "XDG_RUNTIME_DIR";
const BUS_VARIABLE: &str = "DBUS_SESSION_BUS_ADDRESS";

pub struct SystemHost;

impl SystemHost {
    /// A non-interactive ssh session has no user-bus variables; the user's manager (alive through linger) is at the usual place.
    fn user_manager_environment() -> Vec<(&'static str, String)> {
        // SAFETY: `getuid` reads one number and changes nothing.
        let uid = unsafe { libc::getuid() };
        let runtime = std::env::var(RUNTIME_DIR_VARIABLE).unwrap_or_else(|_| format!("/run/user/{uid}"));
        let bus = std::env::var(BUS_VARIABLE).unwrap_or_else(|_| format!("unix:path={runtime}/bus"));
        vec![(RUNTIME_DIR_VARIABLE, runtime), (BUS_VARIABLE, bus)]
    }
}

impl Host for SystemHost {
    fn systemctl(&self, arguments: &[&str]) -> Result<Reply, String> {
        let output = Command::new(SYSTEMCTL).arg("--user").args(arguments).envs(Self::user_manager_environment()).output()
            .map_err(|cause| format!("cannot run systemctl: {cause}"))?;
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string() + String::from_utf8_lossy(&output.stderr).trim();
        Ok(Reply { success: output.status.success(), text })
    }

    fn linger(&self, user: &str) -> Result<bool, String> {
        let output = Command::new(LOGINCTL).args(["show-user", user, "-p", "Linger"]).output().map_err(|cause| format!("cannot run loginctl: {cause}"))?;
        if !output.status.success() {
            return Err(format!("loginctl does not know the login {user}"));
        }
        Ok(String::from_utf8_lossy(&output.stdout).lines().any(|line| line.trim() == LINGER_YES))
    }

    fn process_alive(&self, pid: u32) -> bool {
        // SAFETY: signal 0 only checks that the process exists and can be signalled.
        let found = unsafe { libc::kill(pid as libc::pid_t, 0) };
        found == 0 || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
    }
}
