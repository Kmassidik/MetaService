//! The JSON of `GET /v1/security/events`, exactly as contract/openapi.yaml of the parent writes it.
use serde::Serialize;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    FailedLogin,
    Login,
    Blocked,
    Unblocked,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Method {
    Key,
    Password,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Event {
    pub time: String,
    #[serde(rename = "type")]
    pub kind: EventType,
    pub user: Option<String>,
    pub address: Option<String>,
    pub method: Option<Method>,
    pub count: u32,
    pub until: Option<String>,
    pub detail: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BanTool {
    Running,
    NotRunning,
    NotAvailable,
}

/// The machine's baseline settings. Every field is null when this helper could not tell.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
pub struct Baseline {
    pub password_login: Option<bool>,
    pub ban_tool: Option<BanTool>,
    pub firewall: Option<bool>,
    pub auto_updates: Option<bool>,
    pub starts_after_reboot: Option<bool>,
    pub pending_updates: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Answer {
    pub cursor: String,
    pub reset: bool,
    pub events: Vec<Event>,
    pub baseline: Baseline,
}
