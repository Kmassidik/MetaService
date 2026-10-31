//! What guards the machine: the ban tool, the firewall, automatic updates. Each is read as the helper's own user, and null (None) means "could not tell".
use crate::security::commands::Commands;
use crate::security::env::Environment;
use crate::security::model::BanTool;
use std::time::Duration;

const SYSTEMCTL: &str = "systemctl";
const TIMEOUT: Duration = Duration::from_secs(5);
const BAN_UNITS: [&str; 2] = ["fail2ban.service", "sshguard.service"];
const FIREWALL_UNITS: [&str; 3] = ["ufw.service", "nftables.service", "firewalld.service"];
const UPDATES_UNIT: &str = "unattended-upgrades.service";
const UFW_CONFIG: &str = "/etc/ufw/ufw.conf";
const AUTO_UPGRADES_CONFIG: &str = "/etc/apt/apt.conf.d/20auto-upgrades";
const UNATTENDED_KEY: &str = "APT::Periodic::Unattended-Upgrade";

/// What systemd says of one unit.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Unit {
    pub loaded: bool,
    pub active: bool,
    pub enabled: bool,
}

/// `systemctl show` always answers (even for a unit that does not exist), unlike `is-active`, whose exit code the runner turns into an error.
pub fn unit(commands: &dyn Commands, name: &str) -> Option<Unit> {
    let text = commands
        .run(
            SYSTEMCTL,
            &["show", "-p", "LoadState,ActiveState,UnitFileState", name],
            TIMEOUT,
        )
        .ok()?;
    let value = |key: &str| {
        text.lines()
            .find_map(|line| line.strip_prefix(key)?.strip_prefix('='))
            .map(str::trim)
    };
    let loaded = value("LoadState")? == "loaded";
    Some(Unit {
        loaded,
        active: value("ActiveState") == Some("active"),
        enabled: value("UnitFileState") == Some("enabled"),
    })
}

pub fn ban_tool(commands: &dyn Commands) -> Option<BanTool> {
    let states: Vec<Option<Unit>> = BAN_UNITS.iter().map(|name| unit(commands, name)).collect();
    let known: Vec<Unit> = states.iter().flatten().copied().collect();
    if known.is_empty() {
        return None;
    }
    if known.iter().any(|state| state.active) {
        return Some(BanTool::Running);
    }
    Some(if known.iter().any(|state| state.loaded) {
        BanTool::NotRunning
    } else {
        BanTool::NotAvailable
    })
}

pub fn firewall(env: &Environment, commands: &dyn Commands) -> Option<bool> {
    let ufw_config = std::fs::read_to_string(env.at(UFW_CONFIG))
        .ok()
        .map(|text| config_value(&text, "ENABLED"));
    if ufw_config
        .as_ref()
        .is_some_and(|value| value.as_deref() == Some("yes"))
    {
        return Some(true);
    }
    let states: Vec<Option<Unit>> = FIREWALL_UNITS
        .iter()
        .map(|name| unit(commands, name))
        .collect();
    if states.iter().flatten().any(|state| state.active) {
        return Some(true);
    }
    let answered = ufw_config.is_some() || states.iter().any(Option::is_some);
    answered.then_some(false)
}

pub fn auto_updates(env: &Environment, commands: &dyn Commands) -> Option<bool> {
    let text = std::fs::read_to_string(env.at(AUTO_UPGRADES_CONFIG)).ok()?;
    if !apt_switch_is_on(&text, UNATTENDED_KEY) {
        return Some(false);
    }
    unit(commands, UPDATES_UNIT).map(|state| state.active || state.enabled)
}

/// `KEY=value` or `KEY="value"` in a plain settings file.
fn config_value(text: &str, key: &str) -> Option<String> {
    text.lines()
        .filter_map(|line| {
            line.trim()
                .strip_prefix(key)?
                .trim_start()
                .strip_prefix('=')
        })
        .next()
        .map(|value| value.trim().trim_matches('"').to_ascii_lowercase())
}

/// `APT::Periodic::Unattended-Upgrade "1";` is on; "0", missing or commented out is off.
fn apt_switch_is_on(text: &str, key: &str) -> bool {
    let value = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.starts_with("//") && !line.starts_with('#'))
        .find_map(|line| line.strip_prefix(key))
        .map(|rest| {
            rest.trim()
                .trim_end_matches(';')
                .trim()
                .trim_matches('"')
                .to_string()
        });
    value.is_some_and(|switch| switch != "0" && !switch.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::commands::fake::FakeCommands;

    fn shown(load: &str, active: &str, file: &str) -> String {
        format!("LoadState={load}\nActiveState={active}\nUnitFileState={file}\n")
    }

    fn show(name: &str) -> String {
        format!("systemctl show -p LoadState,ActiveState,UnitFileState {name}")
    }

    fn env_with(files: &[(&str, &str)]) -> (std::path::PathBuf, Environment) {
        let root = std::env::temp_dir().join(format!("ms-svc-{}", rand::random::<u64>()));
        std::fs::create_dir_all(&root).unwrap();
        for (path, text) in files {
            let target = root.join(path.trim_start_matches('/'));
            std::fs::create_dir_all(target.parent().unwrap()).unwrap();
            std::fs::write(target, text).unwrap();
        }
        let env = Environment {
            root: root.clone(),
            home: root.clone(),
            user: "u".into(),
            auth_log: root.join("a"),
            fail2ban_log: root.join("f"),
        };
        (root, env)
    }

    #[test]
    fn the_ban_tool_is_running_stopped_absent_or_unknown() {
        let running = FakeCommands::default()
            .with(
                &show("fail2ban.service"),
                Ok(&shown("loaded", "active", "enabled")),
            )
            .with(
                &show("sshguard.service"),
                Ok(&shown("not-found", "inactive", "")),
            );
        assert_eq!(ban_tool(&running), Some(BanTool::Running));
        let stopped = FakeCommands::default()
            .with(
                &show("fail2ban.service"),
                Ok(&shown("loaded", "inactive", "disabled")),
            )
            .with(
                &show("sshguard.service"),
                Ok(&shown("not-found", "inactive", "")),
            );
        assert_eq!(ban_tool(&stopped), Some(BanTool::NotRunning));
        let absent = FakeCommands::default()
            .with(
                &show("fail2ban.service"),
                Ok(&shown("not-found", "inactive", "")),
            )
            .with(
                &show("sshguard.service"),
                Ok(&shown("not-found", "inactive", "")),
            );
        assert_eq!(ban_tool(&absent), Some(BanTool::NotAvailable));
        let sshguard = FakeCommands::default()
            .with(
                &show("fail2ban.service"),
                Ok(&shown("not-found", "inactive", "")),
            )
            .with(
                &show("sshguard.service"),
                Ok(&shown("loaded", "active", "enabled")),
            );
        assert_eq!(ban_tool(&sshguard), Some(BanTool::Running));
        assert_eq!(
            ban_tool(&FakeCommands::default()),
            None,
            "no systemctl: cannot tell"
        );
    }

    #[test]
    fn the_firewall_from_the_ufw_file_or_a_service() {
        let (root, env) = env_with(&[("/etc/ufw/ufw.conf", "# x\nENABLED=yes\nLOGLEVEL=low\n")]);
        assert_eq!(firewall(&env, &FakeCommands::default()), Some(true));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[("/etc/ufw/ufw.conf", "ENABLED=no\n")]);
        assert_eq!(
            firewall(&env, &FakeCommands::default()),
            Some(false),
            "the file answered"
        );
        let nft = FakeCommands::default().with(
            &show("nftables.service"),
            Ok(&shown("loaded", "active", "enabled")),
        );
        assert_eq!(firewall(&env, &nft), Some(true));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[]);
        assert_eq!(
            firewall(&env, &FakeCommands::default()),
            None,
            "no file and no systemctl: unknown"
        );
        let none = FakeCommands::default().with(
            &show("ufw.service"),
            Ok(&shown("not-found", "inactive", "")),
        );
        assert_eq!(firewall(&env, &none), Some(false));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn automatic_updates_need_the_setting_and_the_service() {
        let on = "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n";
        let service = FakeCommands::default().with(
            &show(UPDATES_UNIT),
            Ok(&shown("loaded", "active", "enabled")),
        );
        let (root, env) = env_with(&[("/etc/apt/apt.conf.d/20auto-upgrades", on)]);
        assert_eq!(auto_updates(&env, &service), Some(true));
        assert_eq!(
            auto_updates(&env, &FakeCommands::default()),
            None,
            "setting on, service unknown"
        );
        let off_service = FakeCommands::default().with(
            &show(UPDATES_UNIT),
            Ok(&shown("loaded", "inactive", "disabled")),
        );
        assert_eq!(auto_updates(&env, &off_service), Some(false));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[(
            "/etc/apt/apt.conf.d/20auto-upgrades",
            "APT::Periodic::Unattended-Upgrade \"0\";\n",
        )]);
        assert_eq!(auto_updates(&env, &service), Some(false));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[]);
        assert_eq!(auto_updates(&env, &service), None, "unreadable");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn small_parsers() {
        assert!(!apt_switch_is_on(
            "// APT::Periodic::Unattended-Upgrade \"1\";\n",
            UNATTENDED_KEY
        ));
        assert!(!apt_switch_is_on("", UNATTENDED_KEY));
        assert!(apt_switch_is_on(
            "APT::Periodic::Unattended-Upgrade \"1\";",
            UNATTENDED_KEY
        ));
        assert_eq!(
            config_value("ENABLED = \"YES\"\n", "ENABLED").as_deref(),
            Some("yes")
        );
    }
}
