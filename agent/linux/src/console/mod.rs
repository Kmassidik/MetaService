//! The console: `GET /v1/workloads/{id}/terminal`, a WebSocket that carries one interactive shell inside a running workload (contract/openapi.yaml).
//!
//! The same bearer-token middleware as every route runs first. Then the checks, in this order: the id is well formed and known (404), the workload
//! runs (409 `not_running`), it has no console yet (409 `console_open`), and the engine can enter it (a VM without the guest agent: 409 `no_agent`).
//! A request without an Upgrade header gets exactly these answers, and 426 when all pass, so a caller can see the reason a refused upgrade hides.
//! The command that runs comes from the engine and the helper's own id only; nothing the browser sends reaches a command line.
mod frames;
mod pty;
mod session;
#[cfg(test)]
mod tests;

use crate::engine::AttachCommand;
use crate::http::{error, failure, App};
use crate::models::{EngineError, Kind, State as RunState, Workload};
use crate::validate::is_id;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use std::collections::HashSet;
use std::sync::{Arc, Mutex};

/// Which workloads have a console open right now. One each.
#[derive(Clone, Default)]
pub struct Consoles {
    open: Arc<Mutex<HashSet<String>>>,
}

/// A workload's one console place. It is given back when this is dropped.
pub struct Slot {
    id: String,
    open: Arc<Mutex<HashSet<String>>>,
}

impl Consoles {
    pub fn is_open(&self, id: &str) -> bool {
        self.open.lock().unwrap().contains(id)
    }

    /// Takes the place of the workload, or None when it already has a console.
    pub fn claim(&self, id: &str) -> Option<Slot> {
        let taken = self.open.lock().unwrap().insert(id.to_string());
        taken.then(|| Slot { id: id.to_string(), open: self.open.clone() })
    }
}

impl Drop for Slot {
    fn drop(&mut self) {
        self.open.lock().unwrap().remove(&self.id);
    }
}

pub async fn terminal(State(app): State<Arc<App>>, Path(id): Path<String>, upgrade: Option<WebSocketUpgrade>) -> Response {
    let command = match checked(&app, &id).await {
        Ok(command) => command,
        Err(reply) => return reply,
    };
    let Some(upgrade) = upgrade else {
        return error(StatusCode::UPGRADE_REQUIRED, "upgrade_required", "this address only speaks WebSocket");
    };
    let Some(slot) = app.consoles.claim(&id) else { return console_open() };
    upgrade
        .max_frame_size(frames::SOCKET_FRAME_BYTES)
        .max_message_size(frames::SOCKET_FRAME_BYTES)
        .on_upgrade(move |socket| session::run(socket, app, id, command, slot))
}

/// Every refusal a console can meet before it starts, as the finished reply.
#[allow(clippy::result_large_err)] // the Err is the reply, sent as it is
async fn checked(app: &Arc<App>, id: &str) -> Result<AttachCommand, Response> {
    if !is_id(id) {
        return Err(not_found());
    }
    let workloads = app.service.workloads().await.map_err(failure)?;
    let workload = workloads.into_iter().find(|w| w.id == id).ok_or_else(not_found)?;
    if workload.state != RunState::Running {
        return Err(error(StatusCode::CONFLICT, "not_running", "the workload is not running"));
    }
    if app.consoles.is_open(id) {
        return Err(console_open());
    }
    attach(app, &workload).await
}

#[allow(clippy::result_large_err)]
async fn attach(app: &Arc<App>, workload: &Workload) -> Result<AttachCommand, Response> {
    let (engine, target) = (app.service.engine.clone(), workload.id.clone());
    match tokio::task::spawn_blocking(move || engine.attach(&target)).await {
        Ok(Ok(command)) => Ok(command),
        Ok(Err(cause)) => Err(attach_failure(workload.kind, cause)),
        Err(cause) => {
            eprintln!("console: the attach task failed: {cause}");
            Err(internal())
        }
    }
}

fn attach_failure(kind: Kind, cause: EngineError) -> Response {
    match (kind, cause) {
        (_, EngineError::NotFound) => not_found(),
        (Kind::Vm, EngineError::Failed(reason)) => error(StatusCode::CONFLICT, "no_agent", &reason),
        (Kind::Container, EngineError::Failed(reason)) => {
            eprintln!("console: could not prepare the shell: {reason}");
            internal()
        }
    }
}

fn not_found() -> Response {
    error(StatusCode::NOT_FOUND, "not_found", "no such thing")
}

fn console_open() -> Response {
    error(StatusCode::CONFLICT, "console_open", "this workload already has a console")
}

fn internal() -> Response {
    error(StatusCode::INTERNAL_SERVER_ERROR, "internal", "internal error").into_response()
}
