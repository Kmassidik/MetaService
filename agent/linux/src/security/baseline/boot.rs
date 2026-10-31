//! Does the helper start again after the machine restarts? True when something enabled launches `metaservice-agent`: a system unit, a user unit
//! of a user that stays logged in at boot (lingering), or an `@reboot` crontab line. False when none does. None when a place could not be read.
use crate::security::commands::Commands;
use crate::security::env::Environment;
use std::io;
use std::path::Path;
use std::time::Duration;

const PROGRAM: &str = "metaservice-agent";
const SYSTEM_UNITS: &str = "/etc/systemd/system";
const LINGER_DIRECTORY: &str = "/var/lib/systemd/linger";
const USER_UNITS: &str = ".config/systemd/user";
const WANTS_SUFFIX: &str = ".wants";
const UNIT_SUFFIX: &str = ".service";
const CRONTAB: &str = "crontab";
const NO_CRONTAB_TEXT: &str = "no crontab";
const REBOOT_MARK: &str = "@reboot";
const TIMEOUT: Duration = Duration::from_secs(5);

pub fn starts_after_reboot(env: &Environment, commands: &dyn Commands) -> Option<bool> {
    let user_units = env.home.join(USER_UNITS);
    let lingering = env.at(LINGER_DIRECTORY).join(&env.user).exists();
    let searched = [
        unit_launches(&env.at(SYSTEM_UNITS)),
        if lingering {
            unit_launches(&user_units)
        } else {
            Ok(false)
        },
        cron_launches(commands),
    ];
    if searched.iter().any(|found| matches!(found, Ok(true))) {
        return Some(true);
    }
    searched.iter().all(Result::is_ok).then_some(false)
}

/// Whether a folder of unit files holds an enabled one (linked from a `*.wants` folder) that runs the program.
fn unit_launches(directory: &Path) -> io::Result<bool> {
    let entries = match std::fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(cause) if cause.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(cause) => return Err(cause),
    };
    let mut names = Vec::new();
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.ends_with(UNIT_SUFFIX) && runs_program(&entry.path())? {
            names.push(name);
        }
    }
    for name in names {
        if is_enabled(directory, &name)? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn runs_program(unit_file: &Path) -> io::Result<bool> {
    match std::fs::read_to_string(unit_file) {
        Ok(text) => Ok(text
            .lines()
            .any(|line| line.trim_start().starts_with("ExecStart") && line.contains(PROGRAM))),
        Err(cause) if cause.kind() == io::ErrorKind::InvalidData => Ok(false),
        Err(cause) => Err(cause),
    }
}

/// An enabled unit has a link to it in some `<target>.wants` folder beside the unit files.
fn is_enabled(directory: &Path, unit: &str) -> io::Result<bool> {
    for entry in std::fs::read_dir(directory)? {
        let entry = entry?;
        let is_wants = entry.file_name().to_string_lossy().ends_with(WANTS_SUFFIX);
        if is_wants && std::fs::symlink_metadata(entry.path().join(unit)).is_ok() {
            return Ok(true);
        }
    }
    Ok(false)
}

fn cron_launches(commands: &dyn Commands) -> io::Result<bool> {
    if !commands.available(CRONTAB) {
        return Ok(false);
    }
    match commands.run(CRONTAB, &["-l"], TIMEOUT) {
        Ok(text) => Ok(text
            .lines()
            .map(str::trim)
            .any(|line| line.starts_with(REBOOT_MARK) && line.contains(PROGRAM))),
        Err(message) if message.to_ascii_lowercase().contains(NO_CRONTAB_TEXT) => Ok(false),
        Err(message) => Err(io::Error::other(message)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::commands::fake::FakeCommands;
    use std::path::PathBuf;

    const UNIT: &str = "[Service]\nExecStart=/home/u/metaservice-agent run\n";

    fn machine() -> (PathBuf, Environment) {
        let root = std::env::temp_dir().join(format!("ms-boot-{}", rand::random::<u64>()));
        std::fs::create_dir_all(root.join("etc/systemd/system/multi-user.target.wants")).unwrap();
        std::fs::create_dir_all(root.join("home/u/.config/systemd/user/default.target.wants"))
            .unwrap();
        let env = Environment {
            root: root.clone(),
            home: root.join("home/u"),
            user: "u".into(),
            auth_log: root.join("a"),
            fail2ban_log: root.join("f"),
        };
        (root, env)
    }

    fn enable(folder: &Path, target: &str, unit: &str) {
        std::fs::write(folder.join(unit), UNIT).unwrap();
        std::os::unix::fs::symlink(folder.join(unit), folder.join(target).join(unit)).unwrap();
    }

    fn no_crontab() -> FakeCommands {
        FakeCommands::default().with("crontab -l", Err("crontab exited with 1: no crontab for u"))
    }

    #[test]
    fn nothing_launching_it_is_false_the_real_finding_of_today() {
        let (root, env) = machine();
        assert_eq!(starts_after_reboot(&env, &no_crontab()), Some(false));
        assert_eq!(
            starts_after_reboot(&env, &FakeCommands::default()),
            Some(false),
            "no crontab program at all is not an error"
        );
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn an_enabled_system_unit_counts_and_a_disabled_one_does_not() {
        let (root, env) = machine();
        std::fs::write(
            root.join("etc/systemd/system/metaservice-agent.service"),
            UNIT,
        )
        .unwrap();
        assert_eq!(
            starts_after_reboot(&env, &no_crontab()),
            Some(false),
            "present but not enabled"
        );
        enable(
            &root.join("etc/systemd/system"),
            "multi-user.target.wants",
            "metaservice-agent.service",
        );
        assert_eq!(starts_after_reboot(&env, &no_crontab()), Some(true));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn a_user_unit_counts_only_when_the_user_lingers() {
        let (root, env) = machine();
        enable(
            &root.join("home/u/.config/systemd/user"),
            "default.target.wants",
            "metaservice-agent.service",
        );
        assert_eq!(
            starts_after_reboot(&env, &no_crontab()),
            Some(false),
            "it would only start at the next login"
        );
        std::fs::create_dir_all(root.join("var/lib/systemd/linger")).unwrap();
        std::fs::write(root.join("var/lib/systemd/linger/u"), "").unwrap();
        assert_eq!(starts_after_reboot(&env, &no_crontab()), Some(true));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn a_unit_for_another_program_does_not_count() {
        let (root, env) = machine();
        let folder = root.join("etc/systemd/system");
        std::fs::write(
            folder.join("other.service"),
            "[Service]\nExecStart=/usr/bin/other\n",
        )
        .unwrap();
        std::os::unix::fs::symlink(
            folder.join("other.service"),
            folder.join("multi-user.target.wants/other.service"),
        )
        .unwrap();
        assert_eq!(starts_after_reboot(&env, &no_crontab()), Some(false));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn an_at_reboot_line_counts_and_a_crontab_failure_is_unknown() {
        let (root, env) = machine();
        let cron = FakeCommands::default().with(
            "crontab -l",
            Ok("# m h\n0 * * * * x\n@reboot /home/u/metaservice-agent run\n"),
        );
        assert_eq!(starts_after_reboot(&env, &cron), Some(true));
        let commented = FakeCommands::default().with(
            "crontab -l",
            Ok("#@reboot /home/u/metaservice-agent run\n@reboot /other\n"),
        );
        assert_eq!(starts_after_reboot(&env, &commented), Some(false));
        let broken = FakeCommands::default().with("crontab -l", Err("crontab took too long"));
        assert_eq!(starts_after_reboot(&env, &broken), None);
        let _ = std::fs::remove_dir_all(root);
    }
}
