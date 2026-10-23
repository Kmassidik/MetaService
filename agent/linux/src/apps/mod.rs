//! Apps on top of a VM (OpenClaw, Hermes): `PUT /v1/workloads/{id}/app`. One constant installer script per app runs inside the running VM as root through
//! `incus exec ms-<id> -- /bin/bash -s` with the script on standard input; nothing from the request reaches the script or the arguments except the choice between the two.
//! The macOS helper does the same in `agent/macos/Sources/AgentCore/Apps/`.
mod report;
pub mod script;
pub mod simulated;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod route_tests;

use crate::engine::Engine;
use crate::models::{EngineError, Refusal, State};
use crate::service::{Failure, Service};
use serde_json::Value;
use std::time::Duration;

pub use report::Installed;

/// The error code of the 502 answer when the app could not be put in the VM.
pub const ERROR_CODE: &str = "app_install_failed";
/// The most an app install may take (the parent waits 25 minutes).
pub const INSTALL_TIMEOUT: Duration = Duration::from_secs(20 * 60);
/// What the person reads when the call itself broke (the VM stopped answering, the time ran out, the output made no sense).
const UNFINISHED_MESSAGE: &str = "The installer did not finish. The VM may have stopped answering or the install took too long.";
const UNREADABLE_MESSAGE: &str = "The VM did not report what happened to the installer.";
const FIELD_APP: &str = "app";
const NAME_OPENCLAW: &str = "openclaw";
const NAME_HERMES: &str = "hermes";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum App {
    Openclaw,
    Hermes,
}

impl App {
    pub fn name(self) -> &'static str {
        match self {
            App::Openclaw => NAME_OPENCLAW,
            App::Hermes => NAME_HERMES,
        }
    }

    /// The constant script for this app.
    pub fn script(self) -> &'static str {
        match self {
            App::Openclaw => script::OPENCLAW_SCRIPT,
            App::Hermes => script::HERMES_SCRIPT,
        }
    }

    /// Reads the request body: an object with exactly one field, `app`, which is `openclaw` or `hermes`.
    pub fn parse(body: &[u8]) -> Result<App, String> {
        let Ok(Value::Object(object)) = serde_json::from_slice::<Value>(body) else { return Err("body must be a JSON object".into()) };
        if let Some(extra) = object.keys().find(|name| name.as_str() != FIELD_APP) {
            return Err(format!("unknown field {extra}"));
        }
        match object.get(FIELD_APP) {
            Some(Value::String(name)) if name == NAME_OPENCLAW => Ok(App::Openclaw),
            Some(Value::String(name)) if name == NAME_HERMES => Ok(App::Hermes),
            _ => Err(format!("{FIELD_APP} must be \"{NAME_OPENCLAW}\" or \"{NAME_HERMES}\"")),
        }
    }
}

/// The `incus` arguments for the install call: a fixed exec of bash reading the script from standard input.
pub fn incus_call(instance: &str) -> Vec<String> {
    ["exec", instance, "--", "/bin/bash", "-s"].iter().map(|part| part.to_string()).collect()
}

/// The 502 answer: plain words and the last lines the installer printed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppError {
    pub message: String,
    pub log_tail: Vec<String>,
}

/// Runs the app's script through the engine and reads what it printed.
pub fn install(engine: &dyn Engine, id: &str, app: App) -> Result<Installed, Failure> {
    let output = match engine.install_app(id, app) {
        Ok(output) => output,
        Err(EngineError::NotFound) => return Err(Failure::NotFound),
        Err(EngineError::Failed(_)) => return Err(Failure::App(AppError { message: UNFINISHED_MESSAGE.into(), log_tail: Vec::new() })),
    };
    let log_tail = report::log_tail(&output);
    match report::parse(&output, app) {
        Some(report::Report::Done(done)) => Ok(done),
        Some(report::Report::Failed(failure)) => Err(Failure::App(AppError { message: failure.message().into(), log_tail })),
        None => Err(Failure::App(AppError { message: UNREADABLE_MESSAGE.into(), log_tail })),
    }
}

impl Service {
    /// Puts the app in one workload. The workload must exist (404) and be running (409 `not_running`).
    pub async fn install_app(&self, id: &str, app: App) -> Result<Installed, Failure> {
        let found = self.workloads().await?.into_iter().find(|w| w.id == id).ok_or(Failure::NotFound)?;
        if found.state != State::Running {
            return Err(Failure::Refused(Refusal { code: "not_running", message: "start it first: an app can only be installed inside a running workload".into(), resource: "state", needed: 1, free: 0 }));
        }
        let engine = self.engine.clone();
        let target = id.to_string();
        tokio::task::spawn_blocking(move || install(engine.as_ref(), &target, app)).await.map_err(|_| Failure::Engine("the install task stopped".into()))?
    }
}
