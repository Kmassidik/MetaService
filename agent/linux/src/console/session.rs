//! One open console: joins the WebSocket to the pty. The shell's output goes to the browser as binary frames; binary frames from the browser are keystrokes,
//! a text frame is a resize. The content of a frame is never logged. The program is ended and reaped on every way out (see `PtyProcess`).
use super::frames::{self, Input, START_SIZE};
use super::pty::{read_output, PtyProcess};
use super::Slot;
use crate::engine::AttachCommand;
use crate::http::App;
use crate::models::State;
use axum::extract::ws::{CloseFrame, Message, WebSocket};
use std::fs::File;
use std::io::Write;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::mpsc::{self, Receiver, Sender};

const CLOSE_NORMAL: u16 = 1000;
const CLOSE_POLICY: u16 = 1008;
const CLOSE_ERROR: u16 = 1011;
/// How often a console checks that its workload still runs. Only open consoles do this.
const WATCH_EVERY: Duration = Duration::from_secs(2);
const OUTPUT_CHUNK_BYTES: usize = 16 * 1024;
/// Chunks waiting between the pty and the socket (and the other way). A full queue slows the pty, which is the point.
const QUEUE_CHUNKS: usize = 32;

/// The sides the session talks to: shell output coming in, keystrokes going out.
type Ends = (Receiver<Vec<u8>>, Sender<Vec<u8>>);

enum Ending {
    /// The browser went away: there is nobody to tell.
    ClientLeft,
    Close(u16, &'static str),
}

pub async fn run(mut socket: WebSocket, app: Arc<App>, id: String, command: AttachCommand, slot: Slot) {
    let process = match PtyProcess::spawn(&command.program, &command.arguments, START_SIZE) {
        Ok(process) => process,
        Err(cause) => {
            eprintln!("console: could not start the shell for {id}: {cause}");
            finish(&mut socket, Ending::Close(CLOSE_ERROR, "the console could not start")).await;
            return;
        }
    };
    eprintln!("console: opened for {id}");
    let ending = serve(&mut socket, &process, &app, &id).await;
    finish(&mut socket, ending).await;
    // Dropping waits up to the grace period, so it happens off the async threads. The place is given back only after the program is gone.
    if let Err(cause) = tokio::task::spawn_blocking(move || drop(process)).await {
        eprintln!("console: ending the shell for {id} failed: {cause}");
    }
    drop(slot);
    eprintln!("console: closed for {id}");
}

async fn finish(socket: &mut WebSocket, ending: Ending) {
    let Ending::Close(code, reason) = ending else { return };
    // A browser that is already gone cannot be told; that is the normal case after a server-side end, not a failure.
    let _ = socket.send(Message::Close(Some(CloseFrame { code, reason: reason.into() }))).await;
}

async fn serve(socket: &mut WebSocket, process: &PtyProcess, app: &App, id: &str) -> Ending {
    let (mut output, keys) = match start_threads(process) {
        Ok(ends) => ends,
        Err(cause) => {
            eprintln!("console: could not attach to the pty for {id}: {cause}");
            return Ending::Close(CLOSE_ERROR, "the console could not start");
        }
    };
    let mut watch = tokio::time::interval(WATCH_EVERY);
    watch.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    watch.tick().await;
    loop {
        let step = tokio::select! {
            chunk = output.recv() => forward_output(socket, chunk).await,
            message = socket.recv() => forward_input(message, process, &keys).await,
            _ = watch.tick() => workload_ended(app, id).await,
        };
        if let Some(ending) = step {
            return ending;
        }
    }
}

/// Starts the two threads that move bytes between the pty and the queues: the receiver of output, and the sender of keystrokes.
fn start_threads(process: &PtyProcess) -> std::io::Result<Ends> {
    let (output_tx, output_rx) = mpsc::channel(QUEUE_CHUNKS);
    let (key_tx, key_rx) = mpsc::channel(QUEUE_CHUNKS);
    let (reader, writer) = (process.reader()?, process.writer()?);
    tokio::task::spawn_blocking(move || pump_output(reader, output_tx));
    tokio::task::spawn_blocking(move || pump_keys(writer, key_rx));
    Ok((output_rx, key_tx))
}

/// Ends when the pty closes (the shell and everything it started are gone) or the socket side is gone.
fn pump_output(mut reader: File, queue: mpsc::Sender<Vec<u8>>) {
    let mut buffer = vec![0u8; OUTPUT_CHUNK_BYTES];
    loop {
        match read_output(&mut reader, &mut buffer) {
            Ok(0) => return,
            Ok(count) if queue.blocking_send(buffer[..count].to_vec()).is_err() => return,
            Ok(_) => {}
            Err(cause) => return eprintln!("console: reading the shell failed: {cause}"),
        }
    }
}

/// Ends when the queue closes. A failed write means the shell is gone, which the output side reports as the end of the console.
fn pump_keys(mut writer: File, mut queue: mpsc::Receiver<Vec<u8>>) {
    while let Some(bytes) = queue.blocking_recv() {
        if writer.write_all(&bytes).is_err() {
            return;
        }
    }
}

async fn forward_output(socket: &mut WebSocket, chunk: Option<Vec<u8>>) -> Option<Ending> {
    let Some(bytes) = chunk else { return Some(Ending::Close(CLOSE_NORMAL, "the shell ended")) };
    socket.send(Message::Binary(bytes)).await.err().map(|_| Ending::ClientLeft)
}

async fn forward_input(message: Option<Result<Message, axum::Error>>, process: &PtyProcess, keys: &mpsc::Sender<Vec<u8>>) -> Option<Ending> {
    let input = match message {
        Some(Ok(Message::Binary(bytes))) => frames::from_binary(&bytes),
        Some(Ok(Message::Text(text))) => frames::from_text(&text),
        Some(Ok(Message::Ping(_) | Message::Pong(_))) => return None,
        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => return Some(Ending::ClientLeft),
    };
    match input {
        Input::Keys(bytes) => keys.send(bytes).await.err().map(|_| Ending::Close(CLOSE_NORMAL, "the shell ended")),
        Input::Resize(size) => process.resize(size).err().map(|cause| {
            eprintln!("console: resize failed: {cause}");
            Ending::Close(CLOSE_ERROR, "the console could not resize")
        }),
        Input::Refused => Some(Ending::Close(CLOSE_POLICY, "that frame is not allowed")),
    }
}

/// Looks at the workload now. A listing that fails is tried again at the next look, not taken for the end.
async fn workload_ended(app: &App, id: &str) -> Option<Ending> {
    let workloads = match app.service.workloads().await {
        Ok(workloads) => workloads,
        Err(_) => {
            eprintln!("console: could not look at the workloads for {id}; trying again");
            return None;
        }
    };
    match workloads.iter().find(|w| w.id == id) {
        None => Some(Ending::Close(CLOSE_NORMAL, "the workload was deleted")),
        Some(found) if found.state != State::Running => Some(Ending::Close(CLOSE_NORMAL, "the workload stopped")),
        Some(_) => None,
    }
}
