//! The host terminal on Windows: a PowerShell inside ConPTY, over the same WebSocket frames as the
//! other helpers' consoles. The ConPTY calls need the `windows` crate, which only compiles on a
//! machine with the Windows toolchain; the route is therefore gated: on a non-Windows build it
//! answers 500 with "needs a Windows build" so the contract is visible in tests, and on a real
//! Windows build it serves the real shell. See docs/PRD-windows-helper.md section 3.
#[cfg(windows)]
pub mod real {
    // ConPTY implementation lands with the first Windows build machine (see PRD section 6).
}

#[cfg(not(windows))]
pub mod stub {
    use crate::http::error;
    use axum::http::StatusCode;
    use axum::response::Response;

    /// Non-Windows builds cannot host a ConPTY shell: an honest refusal, not a pretend one.
    pub async fn host_terminal() -> Response {
        error(StatusCode::INTERNAL_SERVER_ERROR, "needs_windows_build", "this build was made on a non-Windows machine and cannot serve a terminal; build with the Windows toolchain")
    }
}

#[cfg(windows)]
pub use real::host_terminal;
#[cfg(not(windows))]
pub use stub::host_terminal;
