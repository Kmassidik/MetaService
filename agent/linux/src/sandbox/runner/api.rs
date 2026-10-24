//! The runner's one way to reach a sandbox's Firecracker API socket, behind a trait so its tests record calls instead of connecting to anything.
//!
//! The socket is the sandbox's own: each Firecracker process listens on the path inside its jail, and the runner reaches it from the outside through the
//! same jail directory. Nothing here decides what to ask; the request values come from [`crate::sandbox::firecracker::api`], and the runner only hands
//! one to the socket of one sandbox.
use crate::sandbox::firecracker::api::{self, Call};
use std::path::Path;

/// One sandbox's Firecracker API. The only implementation that touches the machine is [`RealApi`].
pub trait Api: Send + Sync {
    /// Makes one call on that sandbox's socket, and answers its refusal in plain words.
    fn call(&self, socket: &Path, call: &Call) -> Result<(), String>;
}

/// The socket itself, with no root needed: the runner is already the only user that may open it.
pub struct RealApi;

impl Api for RealApi {
    fn call(&self, socket: &Path, call: &Call) -> Result<(), String> {
        api::send(socket, call)
    }
}
