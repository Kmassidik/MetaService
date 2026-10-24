//! One sandbox as the contract writes it, and the two bodies the Root sends for sandboxes: a create and a new end time.
//!
//! Everything is read strictly: a field that is not in the contract is refused, a size outside its range is refused, and the id must be the shape the
//! contract gives it. `access_token` is read, checked and dropped: it is never stored, never logged and never returned.
use super::time::iso8601;
use crate::validate::Object;
use serde::ser::SerializeStruct;
use serde::{Serialize, Serializer};
use std::collections::BTreeMap;
use std::sync::OnceLock;

/// Lowercase letters and digits, exactly 20 of them, so `49983-<id>.<domain>` is a host name.
const SANDBOX_ID: &str = r"^[a-z0-9]{20}$";
/// The environment variable names a sandbox gets.
const ENV_KEY: &str = r"^[A-Za-z_][A-Za-z0-9_]{0,127}$";

const MIN_VCPU: u64 = 1;
const MAX_VCPU: u64 = 32;
pub const MIN_RAM_MB: u64 = 256;
const MAX_RAM_MB: u64 = 65536;
pub const MIN_DISK_MB: u64 = 512;
const MAX_DISK_MB: u64 = 102400;
const MAX_ENV_VARS: usize = 100;
const MAX_ENV_VALUE: usize = 16384;
const MIN_TOKEN: usize = 32;
const MAX_TOKEN: usize = 128;

/// The contract's word for a sandbox that is up and taking work. It is the only one this slice can have: a sandbox is ready the moment it exists.
/// `starting`, `pausing`, `paused`, `resuming` and `stopping` arrive with the real engine and with pausing.
pub const STATE_RUNNING: &str = "running";
/// The contract's word for a template a sandbox can be made from. `building` and `failed` arrive when templates are built on the machine.
pub const TEMPLATE_READY: &str = "ready";

/// What happens when the end time comes. `pause` is a later slice; until then a sandbox that asks for it is killed, so it never outlives its time.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum OnEnd {
    Kill,
    Pause,
}

impl OnEnd {
    fn parse(word: &str) -> Option<OnEnd> {
        match word {
            "kill" => Some(OnEnd::Kill),
            "pause" => Some(OnEnd::Pause),
            _ => None,
        }
    }
}

/// A sandbox this helper has: what it was made from, what it may use, and when it ends.
#[derive(Clone, Debug, PartialEq)]
pub struct Sandbox {
    pub id: String,
    pub template: String,
    /// Which build of the template it started from, as the template list names it.
    pub build: String,
    pub vcpu: u32,
    pub ram_mb: u64,
    pub disk_mb: u64,
    pub internet: bool,
    /// Seconds since 1970, UTC.
    pub started_at: u64,
    pub end_at: u64,
    pub on_end: OnEnd,
    /// The in-guest daemon's version, when it said: the simulated engine has no daemon to ask.
    pub daemon_version: Option<String>,
    /// SHA-256 of the create body, so a retry with the same id and the same body is answered with this sandbox instead of a second one.
    fingerprint: String,
}

/// `running_ms` counts up while it runs, so it is worked out from the clock each time the sandbox is sent.
impl Sandbox {
    pub fn new(request: &CreateRequest, build: String, fingerprint: String, now: u64) -> Sandbox {
        Sandbox {
            id: request.id.clone(), template: request.template.clone(), build, vcpu: request.vcpu, ram_mb: request.ram_mb, disk_mb: request.disk_mb,
            internet: request.internet, started_at: now, end_at: request.end_at, on_end: request.on_end, daemon_version: None, fingerprint,
        }
    }

    pub fn fingerprint(&self) -> &str {
        &self.fingerprint
    }

    pub fn running_ms(&self, now: u64) -> u64 {
        now.saturating_sub(self.started_at).saturating_mul(1_000)
    }
}

impl Serialize for Sandbox {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut out = serializer.serialize_struct("Sandbox", 13)?;
        out.serialize_field("id", &self.id)?;
        out.serialize_field("template", &self.template)?;
        out.serialize_field("build", &self.build)?;
        out.serialize_field("state", STATE_RUNNING)?;
        out.serialize_field("vcpu", &self.vcpu)?;
        out.serialize_field("ram_mb", &self.ram_mb)?;
        out.serialize_field("disk_mb", &self.disk_mb)?;
        out.serialize_field("internet", &self.internet)?;
        out.serialize_field("started_at", &iso8601(self.started_at))?;
        out.serialize_field("end_at", &iso8601(self.end_at))?;
        out.serialize_field("on_end", &self.on_end)?;
        out.serialize_field("running_ms", &self.running_ms(super::time::now()))?;
        out.serialize_field("daemon_version", &self.daemon_version)?;
        out.end()
    }
}

/// A create, as the Root sends it.
#[derive(Clone, Debug, PartialEq)]
pub struct CreateRequest {
    pub id: String,
    pub template: String,
    pub vcpu: u32,
    pub ram_mb: u64,
    pub disk_mb: u64,
    pub end_at: u64,
    pub on_end: OnEnd,
    pub internet: bool,
    pub env_vars: BTreeMap<String, String>,
}

impl CreateRequest {
    pub fn parse(body: &[u8]) -> Result<CreateRequest, String> {
        let object = Object::parse(body, &["id", "template", "vcpu", "ram_mb", "disk_mb", "end_at", "on_end", "internet", "env_vars", "access_token"])?;
        let id = object.text("id")?;
        if !is_sandbox_id(id) {
            return Err("id must be 20 lowercase letters or digits".into());
        }
        let request = CreateRequest {
            id: id.to_string(),
            template: object.id("template")?,
            vcpu: object.int("vcpu", MIN_VCPU, MAX_VCPU)? as u32,
            ram_mb: object.int("ram_mb", MIN_RAM_MB, MAX_RAM_MB)?,
            disk_mb: object.int("disk_mb", MIN_DISK_MB, MAX_DISK_MB)?,
            end_at: time_field(&object, "end_at")?,
            on_end: OnEnd::parse(object.choice("on_end", &["kill", "pause"])?).ok_or("on_end must be kill or pause")?,
            internet: object.boolean("internet")?,
            env_vars: env_vars(&object)?,
        };
        check_token(&object)?;
        Ok(request)
    }
}

/// A new end time for a sandbox that already exists.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EndRequest {
    pub end_at: u64,
    pub on_end: OnEnd,
}

impl EndRequest {
    pub fn parse(body: &[u8]) -> Result<EndRequest, String> {
        let object = Object::parse(body, &["end_at", "on_end"])?;
        let on_end = OnEnd::parse(object.choice("on_end", &["kill", "pause"])?).ok_or("on_end must be kill or pause")?;
        Ok(EndRequest { end_at: time_field(&object, "end_at")?, on_end })
    }
}

fn time_field(object: &Object, key: &str) -> Result<u64, String> {
    super::time::parse(object.text(key)?).ok_or_else(|| format!("{key} must be a time like 2026-10-24T09:30:00Z"))
}

fn env_vars(object: &Object) -> Result<BTreeMap<String, String>, String> {
    static KEY: OnceLock<regex::Regex> = OnceLock::new();
    let key_pattern = KEY.get_or_init(|| regex::Regex::new(ENV_KEY).unwrap());
    let sent = object.map("env_vars")?;
    if sent.len() > MAX_ENV_VARS {
        return Err(format!("env_vars may hold at most {MAX_ENV_VARS} names"));
    }
    sent.iter()
        .map(|(name, value)| {
            if !key_pattern.is_match(name) {
                return Err(format!("env_vars name {name} is not a shell name"));
            }
            let Some(text) = value.as_str() else { return Err(format!("env_vars value for {name} must be text")) };
            if text.len() > MAX_ENV_VALUE {
                return Err(format!("env_vars value for {name} is too long"));
            }
            Ok((name.clone(), text.to_string()))
        })
        .collect()
}

/// Checks the access token's shape without keeping it: it is handed to the daemon inside and then forgotten.
fn check_token(object: &Object) -> Result<(), String> {
    let length = object.text("access_token")?.len();
    if (MIN_TOKEN..=MAX_TOKEN).contains(&length) {
        return Ok(());
    }
    Err(format!("access_token must be {MIN_TOKEN} to {MAX_TOKEN} characters"))
}

pub fn is_sandbox_id(text: &str) -> bool {
    static PATTERN: OnceLock<regex::Regex> = OnceLock::new();
    PATTERN.get_or_init(|| regex::Regex::new(SANDBOX_ID).unwrap()).is_match(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sandbox::fingerprint;
    use serde_json::{json, Value};

    const ID: &str = "abcdefghij0123456789";

    fn body(change: impl FnOnce(&mut Value)) -> Vec<u8> {
        let mut sent = json!({"id": ID, "template": "base", "vcpu": 2, "ram_mb": 512, "disk_mb": 1024, "end_at": "2026-10-24T10:00:00Z",
            "on_end": "kill", "internet": true, "env_vars": {"A": "1"}, "access_token": "t".repeat(40)});
        change(&mut sent);
        sent.to_string().into_bytes()
    }

    #[test]
    fn a_good_create_is_read_whole() {
        let request = CreateRequest::parse(&body(|_| {})).ok().unwrap();
        assert_eq!(request.id, ID);
        assert_eq!((request.vcpu, request.ram_mb, request.disk_mb), (2, 512, 1024));
        assert_eq!(request.on_end, OnEnd::Kill);
        assert!(request.internet);
        assert_eq!(request.env_vars.get("A").map(String::as_str), Some("1"));
        assert!(request.end_at > 0);
    }

    #[test]
    fn every_bad_create_is_refused_with_plain_words() {
        let cases: Vec<(&str, Value)> = vec![
            ("upper id", json!("ABCDEFGHIJ0123456789")), ("short id", json!("abc")), ("id with a dash", json!("abcdefghij-123456789")),
            ("id that is a number", json!(12345678901234567890u64)),
        ];
        for (label, value) in cases {
            assert!(CreateRequest::parse(&body(move |sent| sent["id"] = value)).is_err(), "{label}");
        }
        assert!(CreateRequest::parse(&body(|sent| sent["cpu"] = json!(2))).is_err(), "unknown field");
        for (label, sent) in [
            ("vcpu 0", body(|sent| sent["vcpu"] = json!(0))), ("vcpu 33", body(|sent| sent["vcpu"] = json!(33))), ("vcpu text", body(|sent| sent["vcpu"] = json!("2"))),
            ("ram small", body(|sent| sent["ram_mb"] = json!(128))), ("disk large", body(|sent| sent["disk_mb"] = json!(200_000))),
            ("no time", body(|sent| sent["end_at"] = json!("soon"))), ("no on_end", body(|sent| sent["on_end"] = json!("sleep"))),
            ("internet text", body(|sent| sent["internet"] = json!("yes"))), ("env name", body(|sent| sent["env_vars"] = json!({"1BAD": "x"}))),
            ("env value", body(|sent| sent["env_vars"] = json!({"A": 1}))), ("too many env", body(|sent| sent["env_vars"] = json!((0..101).map(|n| (format!("K{n}"), json!("v"))).collect::<serde_json::Map<_, _>>()))),
            ("short token", body(|sent| sent["access_token"] = json!("short"))), ("token number", body(|sent| sent["access_token"] = json!(7))),
        ] {
            assert!(CreateRequest::parse(&sent).is_err(), "{label}");
        }
        assert!(CreateRequest::parse(b"not json").is_err());
        assert!(CreateRequest::parse(b"[]").is_err());
    }

    #[test]
    fn a_good_end_time_is_read_and_kept_out_of_the_fingerprint() {
        let request = EndRequest::parse(br#"{"end_at":"2026-10-24T10:00:00Z","on_end":"pause"}"#).ok().unwrap();
        assert_eq!((request.end_at, request.on_end), (1_792_836_000, OnEnd::Pause));
        assert!(EndRequest::parse(br#"{"end_at":"2026-10-24T10:00:00Z"}"#).is_err());
        assert!(EndRequest::parse(br#"{"end_at":"2026-10-24T10:00:00Z","on_end":"kill","x":1}"#).is_err());
    }

    #[test]
    fn the_answer_carries_the_times_the_contract_writes_and_a_running_time_that_grows() {
        let request = CreateRequest::parse(&body(|_| {})).ok().unwrap();
        let sandbox = Sandbox::new(&request, "1".into(), fingerprint(&body(|_| {})), 1_792_834_200);
        assert_eq!(sandbox.running_ms(1_792_834_200 + 3), 3_000);
        let json = serde_json::to_value(&sandbox).unwrap();
        assert_eq!((json["state"].clone(), json["started_at"].clone(), json["end_at"].clone()), (json!("running"), json!("2026-10-24T09:30:00Z"), json!("2026-10-24T10:00:00Z")));
        assert!(json["daemon_version"].is_null(), "a sandbox with no daemon to ask says null");
        assert_eq!(json.as_object().unwrap().len(), 13);
    }

    #[test]
    fn a_sandbox_id_is_exactly_twenty_lowercase_letters_or_digits() {
        assert!(is_sandbox_id(ID));
        for bad in ["", "abc", "ABCDEFGHIJ0123456789", "abcdefghij01234567890", "abcdefghij-123456789", "abcdefghij 123456789"] {
            assert!(!is_sandbox_id(bad), "{bad}");
        }
    }
}
