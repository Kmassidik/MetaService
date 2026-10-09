//! Remembers every command by its id, so a repeat never runs twice, and survives a restart.
use crate::models::{Command, CommandState};
use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::Mutex;

pub struct Ledger {
    inner: Mutex<Inner>,
    capacity: usize,
    path: Option<PathBuf>,
}

struct Inner {
    commands: HashMap<String, Command>,
    order: VecDeque<String>,
}

impl Ledger {
    pub fn new(capacity: usize, path: Option<PathBuf>) -> Self {
        let restored: Vec<Command> = path.as_ref().and_then(|p| std::fs::read(p).ok()).and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default();
        let mut inner = Inner { commands: HashMap::new(), order: VecDeque::new() };
        let skip = restored.len().saturating_sub(capacity);
        for mut command in restored.into_iter().skip(skip) {
            if matches!(command.state, CommandState::Running | CommandState::Queued) {
                command.state = CommandState::Failed;
                command.result = Some(HashMap::from([("error".to_string(), "the Agent restarted before this finished".to_string())]));
            }
            inner.order.push_back(command.command_id.clone());
            inner.commands.insert(command.command_id.clone(), command);
        }
        Ledger { inner: Mutex::new(inner), capacity, path }
    }

    pub fn find(&self, id: &str) -> Option<Command> {
        self.inner.lock().unwrap().commands.get(id).cloned()
    }

    pub fn record(&self, command: Command) {
        let snapshot = {
            let mut inner = self.inner.lock().unwrap();
            if !inner.commands.contains_key(&command.command_id) {
                inner.order.push_back(command.command_id.clone());
            }
            inner.commands.insert(command.command_id.clone(), command);
            while inner.order.len() > self.capacity {
                if let Some(old) = inner.order.pop_front() {
                    inner.commands.remove(&old);
                }
            }
            inner.order.iter().filter_map(|id| inner.commands.get(id).cloned()).collect::<Vec<_>>()
        };
        self.persist(&snapshot);
    }

    fn persist(&self, commands: &[Command]) {
        let Some(path) = &self.path else { return };
        let Ok(bytes) = serde_json::to_vec(commands) else { return };
        let temporary = path.with_extension("tmp");
        if crate::files::write_private(&temporary, &bytes).is_ok() {
            let _ = std::fs::rename(&temporary, path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::CommandType;

    fn command(id: &str, state: CommandState) -> Command {
        Command { command_id: id.into(), kind: CommandType::Start, state, workload_id: None, result: None }
    }

    #[test]
    fn keeps_commands_and_drops_the_oldest() {
        let ledger = Ledger::new(3, None);
        for index in 1..=5 {
            ledger.record(command(&format!("c{index}"), CommandState::Succeeded));
        }
        assert!(ledger.find("c1").is_none() && ledger.find("c2").is_none() && ledger.find("c5").is_some());
        ledger.record(command("c5", CommandState::Failed));
        assert_eq!(ledger.find("c5").unwrap().state, CommandState::Failed);
        assert!(ledger.find("c3").is_some(), "updating an entry does not push others out");
    }

    #[test]
    fn survives_a_restart_and_fails_what_was_running() {
        let path = std::env::temp_dir().join(format!("ms-ledger-{}.json", rand::random::<u64>()));
        let first = Ledger::new(10, Some(path.clone()));
        first.record(command("done", CommandState::Succeeded));
        first.record(command("busy", CommandState::Running));
        let second = Ledger::new(10, Some(path.clone()));
        assert_eq!(second.find("done").unwrap().state, CommandState::Succeeded);
        let busy = second.find("busy").unwrap();
        assert_eq!(busy.state, CommandState::Failed);
        assert_eq!(busy.result.unwrap()["error"], "the Agent restarted before this finished");
        assert!(second.find("nope").is_none());
        let _ = std::fs::remove_file(path);
    }
}
