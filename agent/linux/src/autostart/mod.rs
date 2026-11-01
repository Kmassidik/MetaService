//! `metaservice-agent autostart on|off|status`: makes the helper start by itself after a reboot, as the login user and without root, by a systemd user unit.
//! Nothing outside the user's home is written. `on` does not start a second copy beside the helper that start.sh started.
mod host;
#[cfg(test)]
mod tests;
mod unit;

use host::{Host, SystemHost};
use serde_json::json;
use std::path::{Path, PathBuf};

/// Everything is in place and will work after a reboot.
pub const EXIT_EFFECTIVE: i32 = 0;
/// The unit is written and enabled, but the owner has one `sudo` line to run (linger).
pub const EXIT_NEEDS_SUDO: i32 = 3;
/// The word after the program's name that `main` hands over to this module.
pub const VERB: &str = "autostart";
const UNIT_FOLDER: &str = ".config/systemd/user";
const START_SCRIPT: &str = "start.sh";
const BOX_OPTION: &str = "--box";
const USAGE: &str = "usage: metaservice-agent autostart on|off|status [--box DIR]";

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action { On, Off, Status }

impl Action {
    fn parse(word: &str) -> Result<Action, String> {
        match word {
            "on" => Ok(Action::On),
            "off" => Ok(Action::Off),
            "status" => Ok(Action::Status),
            _ => Err(USAGE.into()),
        }
    }
}

/// What the verb prints (one line per entry) and the exit code.
#[derive(Debug, PartialEq)]
pub struct Outcome {
    pub code: i32,
    pub lines: Vec<String>,
}

/// The verb as `main` runs it: the exit code, with a failure told on standard error like the other verbs.
pub fn run_verb(arguments: &[String]) -> i32 {
    run(arguments).unwrap_or_else(|message| {
        eprintln!("metaservice-agent: {message}");
        1
    })
}

/// The entry from `main`: the arguments after `autostart`. Prints the outcome and returns the exit code.
pub fn run(arguments: &[String]) -> Result<i32, String> {
    let (action, box_dir) = parse(arguments)?;
    let home = PathBuf::from(std::env::var("HOME").map_err(|_| "HOME is not set")?);
    let user = std::env::var("USER").or_else(|_| std::env::var("LOGNAME")).map_err(|_| "cannot tell which login this is (USER is not set)")?;
    let outcome = Autostart { home, box_dir, user, host: &SystemHost }.perform(action)?;
    outcome.lines.iter().for_each(|line| println!("{line}"));
    Ok(outcome.code)
}

/// The action, and the box: `--box`, or the folder above the folder this program sits in (`<box>/bin/metaservice-agent`).
fn parse(arguments: &[String]) -> Result<(Action, PathBuf), String> {
    let action = Action::parse(arguments.first().ok_or(USAGE)?)?;
    let box_dir = match (arguments.get(1).map(String::as_str), arguments.get(2)) {
        (None, _) => box_of_this_program()?,
        (Some(BOX_OPTION), Some(dir)) if arguments.len() == 3 => PathBuf::from(dir),
        _ => return Err(USAGE.into()),
    };
    Ok((action, box_dir))
}

fn box_of_this_program() -> Result<PathBuf, String> {
    let program = std::env::current_exe().and_then(|path| path.canonicalize()).map_err(|cause| format!("cannot find this program: {cause}"))?;
    program.parent().and_then(Path::parent).map(Path::to_path_buf).ok_or_else(|| "this program is not inside a MetaService folder".to_string())
}

pub struct Autostart<'a> {
    pub home: PathBuf,
    pub box_dir: PathBuf,
    pub user: String,
    pub host: &'a dyn Host,
}

impl Autostart<'_> {
    pub fn perform(&self, action: Action) -> Result<Outcome, String> {
        match action {
            Action::On => self.on(),
            Action::Off => self.off(),
            Action::Status => Ok(self.status()),
        }
    }

    fn unit_file(&self) -> PathBuf { self.home.join(UNIT_FOLDER).join(unit::UNIT_NAME) }

    fn on(&self) -> Result<Outcome, String> {
        let start_script = std::fs::read_to_string(self.box_dir.join(START_SCRIPT)).map_err(|cause| format!("cannot read {START_SCRIPT} in the MetaService folder: {cause}"))?;
        let text = unit::unit_text(&self.box_dir, &unit::start_arguments(&start_script)?)?;
        let mut lines = vec![self.write_unit(&text)?];
        self.require(&["daemon-reload"])?;
        self.require(&["enable", unit::UNIT_NAME])?;
        lines.push("The helper is set to start by itself after a restart.".into());
        lines.push(self.start_if_nothing_runs()?);
        let lingering = self.lingering();
        if !lingering {
            lines.push(format!("One step is left for the owner of this computer: run `sudo loginctl enable-linger {}` once, so the helper can start before anyone logs in.", self.user));
        }
        Ok(Outcome { code: if lingering { EXIT_EFFECTIVE } else { EXIT_NEEDS_SUDO }, lines })
    }

    /// Writes the unit only when its text changed, so a second `on` touches nothing.
    fn write_unit(&self, text: &str) -> Result<String, String> {
        let path = self.unit_file();
        if std::fs::read_to_string(&path).is_ok_and(|current| current == text) {
            return Ok("The start-at-boot file was already in place.".into());
        }
        let folder = path.parent().ok_or("the unit folder has no parent")?;
        std::fs::create_dir_all(folder).map_err(|cause| format!("cannot make {}: {cause}", folder.display()))?;
        std::fs::write(&path, text).map_err(|cause| format!("cannot write {}: {cause}", path.display()))?;
        Ok("Wrote the start-at-boot file.".into())
    }

    /// A helper already running (from start.sh, or from this unit) is left alone: a second copy would only fight it for the port.
    fn start_if_nothing_runs(&self) -> Result<String, String> {
        if self.pid_file_helper_alive() || self.active_by_systemd() {
            return Ok("A helper is already running, so none was started; the start-at-boot file takes effect at the next restart.".into());
        }
        self.require(&["start", unit::UNIT_NAME])?;
        Ok("No helper was running, so the start-at-boot service started one.".into())
    }

    fn off(&self) -> Result<Outcome, String> {
        let path = self.unit_file();
        if !path.exists() {
            return Ok(Outcome { code: EXIT_EFFECTIVE, lines: vec!["Start-at-boot was not on; nothing to remove.".into()] });
        }
        self.require(&["disable", unit::UNIT_NAME])?;
        std::fs::remove_file(&path).map_err(|cause| format!("cannot remove {}: {cause}", path.display()))?;
        self.require(&["daemon-reload"])?;
        Ok(Outcome { code: EXIT_EFFECTIVE, lines: vec!["Start-at-boot is off and its file is removed. A helper that is running was left running.".into()] })
    }

    fn status(&self) -> Outcome {
        let unit_written = self.unit_file().is_file();
        let enabled = self.answers_yes(&["is-enabled", unit::UNIT_NAME]);
        let linger = self.lingering();
        let running_by_systemd = self.active_by_systemd();
        let effective = unit_written && enabled && linger;
        let line = json!({"unit_written": unit_written, "enabled": enabled, "linger": linger, "running_by_systemd": running_by_systemd, "effective": effective});
        Outcome { code: EXIT_EFFECTIVE, lines: vec![line.to_string()] }
    }

    /// A systemctl call that must succeed; its own words are the error.
    fn require(&self, arguments: &[&str]) -> Result<(), String> {
        let reply = self.host.systemctl(arguments)?;
        if reply.success { return Ok(()); }
        Err(format!("`systemctl --user {}` failed: {}", arguments.join(" "), reply.text))
    }

    fn answers_yes(&self, arguments: &[&str]) -> bool { self.host.systemctl(arguments).is_ok_and(|reply| reply.success) }

    fn active_by_systemd(&self) -> bool { self.answers_yes(&["is-active", unit::UNIT_NAME]) }

    fn lingering(&self) -> bool { self.host.linger(&self.user).unwrap_or(false) }

    fn pid_file_helper_alive(&self) -> bool {
        let pid = std::fs::read_to_string(self.box_dir.join(unit::PID_FILE)).ok().and_then(|text| text.trim().parse::<u32>().ok());
        pid.is_some_and(|pid| self.host.process_alive(pid))
    }
}
