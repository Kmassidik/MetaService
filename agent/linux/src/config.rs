//! Settings from the command line. Secrets never go on the command line: the enrollment token comes from a file or an env variable.
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub enum Verb {
    Run,
    Enroll { root: String, name: String, token_file: Option<String> },
    /// One-time host setup. Shows the plan; changes the machine only with `yes`.
    Setup { yes: bool, user: Option<String> },
}

#[derive(Clone, Debug)]
pub struct Config {
    pub verb: Verb,
    pub state_dir: PathBuf,
    pub port: u16,
    pub bind: String,
    pub engine: String,
    pub reserve_ram_mb: Option<u64>,
    pub reserve_disk_gb: Option<u64>,
    pub ram_allowance_mb: Option<u64>,
    pub disk_allowance_gb: Option<u64>,
    pub bad_token_limit: u32,
    pub heartbeat_seconds: u64,
    pub chat_port: u16,
    pub chat_bind: Option<String>,
    pub python_path: Option<String>,
    pub incus_path: Option<String>,
    pub default_image: String,
    pub backup_dir: Option<PathBuf>,
}

pub const VERSION: &str = "0.1.0";
pub const DEFAULT_IMAGE: &str = "images:ubuntu/24.04";
const VALUED: &[&str] = &[
    "--state-dir", "--port", "--bind", "--engine", "--ram-reserve-mb", "--disk-reserve-gb", "--ram-allowance-mb", "--disk-allowance-gb", "--bad-token-limit",
    "--heartbeat-seconds", "--chat-port", "--chat-bind", "--python-path", "--incus-path", "--default-image", "--backup-dir", "--root", "--name", "--enrollment-token-file", "--user",
];

impl Config {
    pub fn parse(arguments: &[String]) -> Result<Config, String> {
        let (verb, rest) = match arguments.first() {
            Some(first) if !first.starts_with("--") => (first.as_str(), &arguments[1..]),
            _ => ("run", arguments),
        };
        let options = Self::options(rest)?;
        let mut config = Config::defaults();
        config.apply(&options)?;
        config.verb = match verb {
            "run" => Verb::Run,
            "enroll" => Verb::Enroll {
                root: options.get("--root").cloned().ok_or("enroll needs --root and --name")?,
                name: options.get("--name").cloned().ok_or("enroll needs --root and --name")?,
                token_file: options.get("--enrollment-token-file").cloned(),
            },
            "setup" => Verb::Setup { yes: options.contains_key("--yes"), user: options.get("--user").cloned() },
            other => return Err(format!("unknown command {other}; use run, enroll or setup")),
        };
        Ok(config)
    }

    fn defaults() -> Config {
        Config {
            verb: Verb::Run,
            state_dir: PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".into())).join(".metaservice-agent"),
            port: 9101, bind: "127.0.0.1".into(), engine: "simulated".into(), reserve_ram_mb: None, reserve_disk_gb: None, ram_allowance_mb: None, disk_allowance_gb: None,
            bad_token_limit: 10, heartbeat_seconds: 15, chat_port: 9200, chat_bind: None, python_path: None, incus_path: None, default_image: DEFAULT_IMAGE.into(), backup_dir: None,
        }
    }

    fn options(arguments: &[String]) -> Result<HashMap<String, String>, String> {
        let mut found = HashMap::new();
        let mut items = arguments.iter();
        while let Some(name) = items.next() {
            if name == "--yes" {
                found.insert(name.clone(), String::new());
                continue;
            }
            let value = items.next().filter(|_| VALUED.contains(&name.as_str())).ok_or_else(|| format!("unknown or incomplete option {name}"))?;
            found.insert(name.clone(), value.clone());
        }
        Ok(found)
    }

    fn apply(&mut self, options: &HashMap<String, String>) -> Result<(), String> {
        if let Some(dir) = options.get("--state-dir") { self.state_dir = PathBuf::from(dir); }
        if let Some(bind) = options.get("--bind") { self.bind = bind.clone(); }
        if let Some(engine) = options.get("--engine") { self.engine = engine.clone(); }
        if !["simulated", "incus"].contains(&self.engine.as_str()) {
            return Err("--engine must be simulated or incus".into());
        }
        self.port = number(options, "--port", 1, 65535)?.map_or(self.port, |n| n as u16);
        self.chat_port = number(options, "--chat-port", 1, 65535)?.map_or(self.chat_port, |n| n as u16);
        self.bad_token_limit = number(options, "--bad-token-limit", 1, 1_000_000)?.map_or(self.bad_token_limit, |n| n as u32);
        self.heartbeat_seconds = number(options, "--heartbeat-seconds", 1, 3600)?.unwrap_or(self.heartbeat_seconds);
        self.reserve_ram_mb = number(options, "--ram-reserve-mb", 0, 100_000_000)?;
        self.reserve_disk_gb = number(options, "--disk-reserve-gb", 0, 100_000_000)?;
        self.ram_allowance_mb = number(options, "--ram-allowance-mb", 1, 100_000_000)?;
        self.disk_allowance_gb = number(options, "--disk-allowance-gb", 1, 100_000_000)?;
        self.chat_bind = options.get("--chat-bind").cloned();
        self.python_path = options.get("--python-path").cloned();
        self.incus_path = options.get("--incus-path").cloned();
        if let Some(image) = options.get("--default-image") { self.default_image = image.clone(); }
        self.backup_dir = options.get("--backup-dir").map(PathBuf::from);
        Ok(())
    }

    /// What the Agent shows the Root (heartbeats).
    pub fn token_file(&self) -> PathBuf { self.state_dir.join("agent.token") }
    /// What the Root shows the Agent (commands). The Agent API accepts only this.
    pub fn command_token_file(&self) -> PathBuf { self.state_dir.join("command.token") }
    pub fn settings_file(&self) -> PathBuf { self.state_dir.join("agent.json") }
}

fn number(options: &HashMap<String, String>, name: &str, low: u64, high: u64) -> Result<Option<u64>, String> {
    let Some(text) = options.get(name) else { return Ok(None) };
    match text.parse::<u64>() {
        Ok(value) if (low..=high).contains(&value) => Ok(Some(value)),
        _ => Err(format!("{text} is not a number between {low} and {high}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(items: &[&str]) -> Result<Config, String> {
        Config::parse(&items.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn defaults_and_options() {
        let config = parse(&["run", "--port", "9999", "--engine", "incus", "--ram-allowance-mb", "8000"]).unwrap();
        assert_eq!((config.port, config.engine.as_str(), config.ram_allowance_mb, config.bind.as_str()), (9999, "incus", Some(8000), "127.0.0.1"));
        assert!(matches!(parse(&[]).unwrap().verb, Verb::Run));
        assert!(matches!(parse(&["--port", "9100"]).unwrap().verb, Verb::Run), "no verb means run");
    }

    #[test]
    fn bad_input_is_refused() {
        for bad in [&["--nope", "1"][..], &["--port"], &["--port", "0"], &["--port", "99999"], &["--port", "x"], &["--engine", "docker"], &["fly"], &["enroll", "--root", "http://x"],
                    &["enroll", "--name", "x"], &["run", "--enrollment-token", "secret"]] {
            assert!(parse(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn enroll_never_takes_the_token_as_a_plain_argument() {
        let setup = parse(&["setup", "--yes", "--user", "kurnia"]).unwrap();
        assert!(matches!(setup.verb, Verb::Setup { yes: true, user: Some(ref u) } if u == "kurnia"));
        assert!(matches!(parse(&["setup"]).unwrap().verb, Verb::Setup { yes: false, user: None }));
        let config = parse(&["enroll", "--root", "http://10.0.0.1:9100", "--name", "dgx", "--enrollment-token-file", "/tmp/t"]).unwrap();
        assert!(matches!(config.verb, Verb::Enroll { ref name, token_file: Some(_), .. } if name == "dgx"));
    }
}
