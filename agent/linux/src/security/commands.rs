//! The few programs the baseline and the journal fallback ask (`systemctl`, `crontab`, `apt`, `journalctl`), behind a trait so tests script them.
//! The real one is the engine's `ProcessRunner`, which has a time limit on every call and a cap on what it reads.
use crate::incus::{ProcessRunner, Runner};
use crate::models::EngineError;
use std::path::PathBuf;
use std::time::Duration;

/// Where a normal user's PATH may leave out the system programs we ask for.
const EXTRA_DIRECTORIES: [&str; 4] = ["/usr/sbin", "/sbin", "/usr/bin", "/bin"];

pub trait Commands: Send + Sync {
    /// Whether the program exists on this machine.
    fn available(&self, program: &str) -> bool;
    /// Runs it with a time limit; Err carries a short plain text (a program that exits with an error is an Err too).
    fn run(&self, program: &str, arguments: &[&str], timeout: Duration) -> Result<String, String>;
}

pub struct SystemCommands;

impl Commands for SystemCommands {
    fn available(&self, program: &str) -> bool {
        find(program).is_some()
    }

    fn run(&self, program: &str, arguments: &[&str], timeout: Duration) -> Result<String, String> {
        let path = find(program).ok_or_else(|| format!("{program} is not installed"))?;
        let runner = ProcessRunner {
            path: path.to_string_lossy().into_owned(),
        };
        let owned: Vec<String> = arguments
            .iter()
            .map(|argument| argument.to_string())
            .collect();
        runner.run(&owned, timeout).map_err(|cause| match cause {
            EngineError::NotFound => format!("{program} was not found"),
            EngineError::Failed(message) => message,
        })
    }
}

fn find(program: &str) -> Option<PathBuf> {
    find_in(&std::env::var("PATH").unwrap_or_default(), program)
}

fn find_in(search_path: &str, program: &str) -> Option<PathBuf> {
    let directories = search_path
        .split(':')
        .filter(|part| !part.is_empty())
        .chain(EXTRA_DIRECTORIES);
    directories
        .map(|directory| PathBuf::from(directory).join(program))
        .find(|candidate| candidate.is_file())
}

#[cfg(test)]
pub mod fake {
    use super::Commands;
    use std::collections::HashMap;
    use std::sync::Mutex;
    use std::time::Duration;

    /// Answers by `program arg arg`. A program with no answer is not installed.
    #[derive(Default)]
    pub struct FakeCommands {
        answers: HashMap<String, Result<String, String>>,
        pub calls: Mutex<Vec<String>>,
    }

    impl FakeCommands {
        pub fn with(mut self, line: &str, answer: Result<&str, &str>) -> Self {
            self.answers.insert(
                line.into(),
                answer.map(str::to_string).map_err(str::to_string),
            );
            self
        }
    }

    impl Commands for FakeCommands {
        fn available(&self, program: &str) -> bool {
            self.answers
                .keys()
                .any(|line| line.split(' ').next() == Some(program))
        }

        fn run(
            &self,
            program: &str,
            arguments: &[&str],
            _timeout: Duration,
        ) -> Result<String, String> {
            let line = std::iter::once(program)
                .chain(arguments.iter().copied())
                .collect::<Vec<_>>()
                .join(" ");
            self.calls.lock().unwrap().push(line.clone());
            self.answers
                .get(&line)
                .cloned()
                .unwrap_or_else(|| Err(format!("no answer scripted for {line}")))
        }
    }
}
