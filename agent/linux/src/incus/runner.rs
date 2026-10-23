//! The `incus` program behind a trait so tests can script it: the real one has a time limit on every call and can be given standard input.
use crate::models::EngineError;
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// The most a program may print before we stop reading (it then runs into the time limit and is stopped).
const MAX_OUTPUT_BYTES: u64 = 4 * 1024 * 1024;

/// The name `incus` is looked up by when a runner has no path of its own (scripted runners in tests).
pub const DEFAULT_PROGRAM: &str = "incus";

pub trait Runner: Send + Sync {
    /// The program this runner starts, for callers that must start it themselves on a pty.
    fn program(&self) -> String {
        DEFAULT_PROGRAM.into()
    }
    fn run(&self, arguments: &[String], timeout: Duration) -> Result<String, EngineError>;
    /// Like `run`, with `input` sent on the program's standard input (never in the arguments).
    fn run_with_input(&self, arguments: &[String], input: &[u8], timeout: Duration) -> Result<String, EngineError>;
}

/// The real `incus` program, with a time limit on every call.
pub struct ProcessRunner {
    pub path: String,
}

impl Runner for ProcessRunner {
    fn program(&self) -> String {
        self.path.clone()
    }

    fn run(&self, arguments: &[String], timeout: Duration) -> Result<String, EngineError> {
        self.call(arguments, None, timeout)
    }

    fn run_with_input(&self, arguments: &[String], input: &[u8], timeout: Duration) -> Result<String, EngineError> {
        self.call(arguments, Some(input), timeout)
    }
}

impl ProcessRunner {
    fn call(&self, arguments: &[String], input: Option<&[u8]>, timeout: Duration) -> Result<String, EngineError> {
        let stdin = if input.is_some() { Stdio::piped() } else { Stdio::null() };
        let mut child = Command::new(&self.path).args(arguments).stdin(stdin).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
        let feeder = input.and_then(|bytes| child.stdin.take().map(|pipe| feed(pipe, bytes.to_vec())));
        let mut stdout = child.stdout.take().expect("piped").take(MAX_OUTPUT_BYTES);
        let mut stderr = child.stderr.take().expect("piped").take(MAX_OUTPUT_BYTES);
        let reader = std::thread::spawn(move || { let mut text = String::new(); let _ = stdout.read_to_string(&mut text); text });
        let errors = std::thread::spawn(move || { let mut text = String::new(); let _ = stderr.read_to_string(&mut text); text });
        let deadline = Instant::now() + timeout;
        let status = loop {
            if let Some(status) = child.try_wait()? { break status; }
            if Instant::now() >= deadline {
                let _ = child.kill();
                let _ = child.wait();
                return Err(EngineError::Failed(format!("incus {} took too long", arguments.first().map(String::as_str).unwrap_or(""))));
            }
            std::thread::sleep(Duration::from_millis(50));
        };
        let (output, errors) = (reader.join().unwrap_or_default(), errors.join().unwrap_or_default());
        drop(feeder);
        if status.success() { Ok(output) } else { Err(EngineError::Failed(format!("incus {} exited with {}: {}", arguments.first().map(String::as_str).unwrap_or(""), status.code().unwrap_or(-1), errors.chars().rev().take(300).collect::<String>().chars().rev().collect::<String>()))) }
    }
}

/// Sends the bytes to the program's standard input from another thread (so a program that prints before it reads cannot block us), then closes it.
/// A program that quits before reading everything makes the write fail; its exit status and error text already say so.
fn feed(mut pipe: std::process::ChildStdin, bytes: Vec<u8>) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || { let _ = pipe.write_all(&bytes); })
}
