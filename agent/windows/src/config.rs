//! Settings from the command line. Secrets never go on the command line: the enrollment token comes from a file.
use std::collections::HashMap;
use std::path::PathBuf;

pub const VERSION: &str = "0.1.0";

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verb {
    /// Serve the helper API. The default.
    Run,
    /// One-time enrolment against the parent: proves this machine with the join's token.
    Enroll { root: String, name: String, token_file: Option<String> },
    /// One-time host setup: installs the scheduled task. Shows the plan; changes the machine only with `yes`.
    Setup { yes: bool },
}

pub struct Config {
    pub verb: Verb,
    pub state_dir: PathBuf,
    pub port: u16,
    pub bind: String,
    pub heartbeat_seconds: u64,
    pub bad_token_limit: u32,
}

const OPTIONS_WITH_VALUE: &[&str] = &["--root", "--name", "--enrollment-token-file", "--port", "--bind", "--heartbeat-seconds", "--state-dir"];
const FLAGS: &[&str] = &["--yes"];

impl Config {
    pub fn parse(arguments: &[String]) -> Result<Config, String> {
        let (verb, rest) = match arguments.first() {
            Some(first) if !first.starts_with("--") => (first.as_str(), &arguments[1..]),
            _ => ("run", arguments),
        };
        let options = Self::options(rest)?;
        let mut config = Self::defaults();
        config.apply(&options)?;
        config.verb = match verb {
            "run" => Verb::Run,
            "enroll" => Verb::Enroll {
                root: options.get("--root").cloned().ok_or("enroll needs --root and --name")?,
                name: options.get("--name").cloned().ok_or("enroll needs --root and --name")?,
                token_file: options.get("--enrollment-token-file").cloned(),
            },
            "setup" => Verb::Setup { yes: options.contains_key("--yes") },
            other => return Err(format!("unknown command {other}; use run, enroll or setup")),
        };
        Ok(config)
    }

    fn defaults() -> Config {
        Config {
            verb: Verb::Run,
            state_dir: std::env::var("USERPROFILE").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from(".")).join(".metaservice-join").join("state"),
            port: 9101,
            bind: "10.77.0.2".into(),
            heartbeat_seconds: 15,
            bad_token_limit: 10,
        }
    }

    fn apply(&mut self, options: &HashMap<String, String>) -> Result<(), String> {
        if let Some(port) = options.get("--port") {
            self.port = port.parse().map_err(|_| "--port must be a number")?;
        }
        if let Some(bind) = options.get("--bind") {
            self.bind = bind.clone();
        }
        if let Some(seconds) = options.get("--heartbeat-seconds") {
            self.heartbeat_seconds = seconds.parse().map_err(|_| "--heartbeat-seconds must be a number")?;
        }
        if let Some(dir) = options.get("--state-dir") {
            self.state_dir = PathBuf::from(dir);
        }
        Ok(())
    }

    fn options(arguments: &[String]) -> Result<HashMap<String, String>, String> {
        let mut found = HashMap::new();
        let mut items = arguments.iter();
        while let Some(name) = items.next() {
            if FLAGS.contains(&name.as_str()) {
                found.insert(name.clone(), String::new());
                continue;
            }
            let Some(value) = items.next() else {
                return Err(format!("{name} needs a value"));
            };
            if !OPTIONS_WITH_VALUE.contains(&name.as_str()) {
                return Err(format!("unknown option {name}"));
            }
            found.insert(name.clone(), value.clone());
        }
        Ok(found)
    }
}

