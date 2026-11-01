//! What guards the machine: the ban tool, the firewall, automatic updates. Each is read as the helper's own user, and null (None) means "could not tell".
use crate::security::commands::Commands;
use crate::security::env::Environment;
use crate::security::model::BanTool;
use std::time::Duration;

const SYSTEMCTL: &str = "systemctl";
const TIMEOUT: Duration = Duration::from_secs(5);
const BAN_UNITS: [&str; 2] = ["fail2ban.service", "sshguard.service"];
const FIREWALLD_UNIT: &str = "firewalld.service";
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
    // A Linux machine can have a ban tool, so "none installed" is as much a warning as "installed but stopped". `NotAvailable` is for machines that cannot have one (macOS).
    Some(BanTool::NotRunning)
}

/// ufw.conf decides for ufw: its systemd unit is a one-shot that is "active" even when the firewall is disabled, and an active nftables unit
/// says nothing about the rules, so neither unit counts. firewalld being active does.
pub fn firewall(env: &Environment, commands: &dyn Commands) -> Option<bool> {
    let ufw_enabled = std::fs::read_to_string(env.at(UFW_CONFIG))
        .ok()
        .map(|text| config_value(&text, "ENABLED").as_deref() == Some("yes"));
    if ufw_enabled == Some(true) || unit(commands, FIREWALLD_UNIT).is_some_and(|state| state.active)
    {
        return Some(true);
    }
    ufw_enabled
}

/// A package that is not installed, or a service that is off, means no automatic updates; both on and the setting at "1" means yes.
pub fn auto_updates(env: &Environment, commands: &dyn Commands) -> Option<bool> {
    let state = unit(commands, UPDATES_UNIT)?;
    if !(state.loaded && state.active && state.enabled) {
        return Some(false);
    }
    let text = std::fs::read_to_string(env.at(AUTO_UPGRADES_CONFIG)).ok()?;
    Some(apt_switch_is_on(&text, UNATTENDED_KEY))
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
        assert_eq!(ban_tool(&absent), Some(BanTool::NotRunning));
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

    /// The real state of the RTX PC and the DGX Spark: ufw.service active and enabled, yet ufw.conf says ENABLED=no.
    fn real_machine() -> FakeCommands {
        FakeCommands::default()
            .with(
                &show("ufw.service"),
                Ok(&shown("loaded", "active", "enabled")),
            )
            .with(
                &show("nftables.service"),
                Ok(&shown("loaded", "inactive", "disabled")),
            )
            .with(
                &show("firewalld.service"),
                Ok(&shown("not-found", "inactive", "")),
            )
    }

    #[test]
    fn the_firewall_follows_ufw_conf_and_firewalld_never_the_ufw_or_nftables_unit() {
        let (root, env) = env_with(&[("/etc/ufw/ufw.conf", "# x\nENABLED=no\nLOGLEVEL=low\n")]);
        assert_eq!(
            firewall(&env, &real_machine()),
            Some(false),
            "ufw unit active but ENABLED=no"
        );
        let firewalld = FakeCommands::default().with(
            &show("firewalld.service"),
            Ok(&shown("loaded", "active", "enabled")),
        );
        assert_eq!(
            firewall(&env, &firewalld),
            Some(true),
            "firewalld on beats ufw off"
        );
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[("/etc/ufw/ufw.conf", "ENABLED=yes\n")]);
        assert_eq!(firewall(&env, &FakeCommands::default()), Some(true));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[]);
        assert_eq!(
            firewall(&env, &real_machine()),
            None,
            "no ufw.conf: the unit says nothing"
        );
        let nft = FakeCommands::default().with(
            &show("nftables.service"),
            Ok(&shown("loaded", "active", "enabled")),
        );
        assert_eq!(
            firewall(&env, &nft),
            None,
            "nftables alone says nothing about the rules"
        );
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn automatic_updates_are_false_when_absent_or_off_and_true_only_with_service_and_setting() {
        let on = "APT::Periodic::Update-Package-Lists \"1\";\nAPT::Periodic::Unattended-Upgrade \"1\";\n";
        let active = FakeCommands::default().with(
            &show(UPDATES_UNIT),
            Ok(&shown("loaded", "active", "enabled")),
        );
        let (root, env) = env_with(&[("/etc/apt/apt.conf.d/20auto-upgrades", on)]);
        assert_eq!(auto_updates(&env, &active), Some(true));
        let off_service = FakeCommands::default().with(
            &show(UPDATES_UNIT),
            Ok(&shown("loaded", "inactive", "disabled")),
        );
        assert_eq!(auto_updates(&env, &off_service), Some(false));
        let spark = FakeCommands::default()
            .with(&show(UPDATES_UNIT), Ok(&shown("not-found", "inactive", "")));
        assert_eq!(
            auto_updates(&env, &spark),
            Some(false),
            "the package is not installed"
        );
        assert_eq!(
            auto_updates(&env, &FakeCommands::default()),
            None,
            "no systemctl"
        );
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[(
            "/etc/apt/apt.conf.d/20auto-upgrades",
            "APT::Periodic::Unattended-Upgrade \"0\";\n",
        )]);
        assert_eq!(auto_updates(&env, &active), Some(false));
        let _ = std::fs::remove_dir_all(root);
        let (root, env) = env_with(&[]);
        assert_eq!(
            auto_updates(&env, &active),
            None,
            "service on but the setting file is unreadable"
        );
        assert_eq!(auto_updates(&env, &spark), Some(false));
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
