//! The baseline: how well the machine is set up against logins from outside. Every check is read-only and runs as the helper's own user.
//! The whole baseline is kept for five minutes, and the count of pending security updates (which runs `apt`) for ten.
mod boot;
mod services;
mod sshd;

use super::commands::Commands;
use super::env::Environment;
use super::model::Baseline;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const BASELINE_TTL: Duration = Duration::from_secs(5 * 60);
const PENDING_TTL: Duration = Duration::from_secs(10 * 60);
const APT: &str = "apt";
const APT_TIMEOUT: Duration = Duration::from_secs(30);
const SECURITY_MARK: &str = "-security";

/// A value and when it was read.
struct Kept<T>(Mutex<Option<(Instant, T)>>);

impl<T: Clone> Kept<T> {
    fn new() -> Kept<T> {
        Kept(Mutex::new(None))
    }

    fn get(&self, ttl: Duration, read: impl FnOnce() -> T) -> T {
        let mut slot = self
            .0
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        if let Some((_, value)) = slot.as_ref().filter(|(at, _)| at.elapsed() < ttl) {
            return value.clone();
        }
        let value = read();
        *slot = Some((Instant::now(), value.clone()));
        value
    }
}

pub struct BaselineReader {
    whole: Kept<Baseline>,
    pending: Kept<Option<u32>>,
}

impl BaselineReader {
    pub fn new() -> BaselineReader {
        BaselineReader {
            whole: Kept::new(),
            pending: Kept::new(),
        }
    }

    pub fn current(&self, env: &Environment, commands: &dyn Commands) -> Baseline {
        self.whole.get(BASELINE_TTL, || Baseline {
            password_login: sshd::password_login(env),
            ban_tool: services::ban_tool(commands),
            firewall: services::firewall(env, commands),
            auto_updates: services::auto_updates(env, commands),
            starts_after_reboot: boot::starts_after_reboot(env, commands),
            pending_updates: self.pending.get(PENDING_TTL, || pending_updates(commands)),
        })
    }
}

/// How many upgradable packages come from a security pocket. None when apt is missing or fails.
fn pending_updates(commands: &dyn Commands) -> Option<u32> {
    if !commands.available(APT) {
        return None;
    }
    let listing = commands
        .run(APT, &["list", "--upgradable"], APT_TIMEOUT)
        .ok()?;
    u32::try_from(
        listing
            .lines()
            .filter(|line| line.contains(SECURITY_MARK))
            .count(),
    )
    .ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::commands::fake::FakeCommands;

    const LISTING: &str = "Listing...\nopenssl/noble-updates,noble-security 3.0.13 amd64 [upgradable from: 3.0.12]\nvim/noble-updates 9.1 amd64 [upgradable from: 9.0]\nlibc6/noble-security,noble-updates 2.39 amd64 [upgradable from: 2.38]\n";

    #[test]
    fn pending_updates_count_the_security_lines() {
        let apt = FakeCommands::default().with("apt list --upgradable", Ok(LISTING));
        assert_eq!(pending_updates(&apt), Some(2));
        assert_eq!(pending_updates(&FakeCommands::default()), None, "no apt");
        let broken =
            FakeCommands::default().with("apt list --upgradable", Err("apt took too long"));
        assert_eq!(pending_updates(&broken), None);
    }

    #[test]
    fn the_baseline_is_kept_and_apt_runs_once() {
        let root = std::env::temp_dir().join(format!("ms-base-{}", rand::random::<u64>()));
        let env = Environment {
            root: root.clone(),
            home: root.clone(),
            user: "u".into(),
            auth_log: root.join("a"),
            fail2ban_log: root.join("f"),
        };
        let commands = FakeCommands::default().with("apt list --upgradable", Ok(LISTING));
        let reader = BaselineReader::new();
        let first = reader.current(&env, &commands);
        let second = reader.current(&env, &commands);
        assert_eq!(
            (first, first.pending_updates, first.password_login),
            (second, Some(2), None)
        );
        let apt_runs = commands
            .calls
            .lock()
            .unwrap()
            .iter()
            .filter(|call| call.starts_with("apt "))
            .count();
        assert_eq!(apt_runs, 1);
    }
}
