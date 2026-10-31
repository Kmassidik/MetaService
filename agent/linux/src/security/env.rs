//! Where this machine keeps what the security reader looks at. Everything is a path under `root`, so tests build a whole machine in a temp folder.
use std::path::{Path, PathBuf};

const AUTH_LOG: &str = "/var/log/auth.log";
const FAIL2BAN_LOG: &str = "/var/log/fail2ban.log";
const ROTATED_SUFFIX: &str = ".1";

#[derive(Clone, Debug)]
pub struct Environment {
    pub root: PathBuf,
    pub home: PathBuf,
    pub user: String,
    pub auth_log: PathBuf,
    pub fail2ban_log: PathBuf,
}

impl Environment {
    pub fn system() -> Environment {
        let root = PathBuf::from("/");
        let home = PathBuf::from(std::env::var("HOME").unwrap_or_default());
        let user = std::env::var("USER")
            .or_else(|_| std::env::var("LOGNAME"))
            .unwrap_or_default();
        Environment {
            auth_log: root.join(AUTH_LOG.trim_start_matches('/')),
            fail2ban_log: root.join(FAIL2BAN_LOG.trim_start_matches('/')),
            root,
            home,
            user,
        }
    }

    /// An absolute path of the machine (`/etc/ssh/sshd_config`) as a path on disk.
    pub fn at(&self, absolute: &str) -> PathBuf {
        self.root.join(absolute.trim_start_matches('/'))
    }

    pub fn with_logs(mut self, auth: PathBuf, fail2ban: PathBuf) -> Environment {
        self.auth_log = auth;
        self.fail2ban_log = fail2ban;
        self
    }
}

/// `auth.log` -> `auth.log.1`, the file logrotate leaves.
pub fn rotated(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_os_string();
    name.push(ROTATED_SUFFIX);
    PathBuf::from(name)
}
