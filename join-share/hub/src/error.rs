//! One JSON error type for every HTTP route.
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::{json, Value};
use std::fmt::Display;

#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub body: Value,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &str) -> Self {
        Self { status, body: json!({ "error": code }) }
    }

    pub fn bad(code: &str) -> Self {
        Self::new(StatusCode::BAD_REQUEST, code)
    }

    pub fn with(mut self, key: &str, value: impl Into<Value>) -> Self {
        self.body[key] = value.into();
        self
    }

    /// Same answer for unknown, expired and used links: no hint which.
    pub fn unknown_link() -> Self {
        Self::new(StatusCode::NOT_FOUND, "unknown_link")
    }

    /// The reason is logged, never sent to the caller.
    pub fn internal(reason: impl Display) -> Self {
        eprintln!("join-share: internal error: {reason}");
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, "internal")
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        Self::internal(e)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(self.body)).into_response()
    }
}
