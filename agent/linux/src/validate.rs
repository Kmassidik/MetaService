//! Requests are read strictly: unknown fields are refused and every field is checked for type, size and shape.
use crate::models::{GpuMode, Kind};
use regex::Regex;
use serde_json::{Map, Value};
use std::sync::OnceLock;

fn id_pattern() -> &'static Regex {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[a-z0-9][a-z0-9-]{0,62}$").unwrap())
}

pub fn is_id(text: &str) -> bool {
    id_pattern().is_match(text)
}

pub fn is_semver(text: &str) -> bool {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[0-9]+\.[0-9]+\.[0-9]+$").unwrap()).is_match(text) && text.len() <= 32
}

fn is_image(text: &str) -> bool {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[a-z0-9][a-z0-9._:/-]{0,127}$").unwrap()).is_match(text)
}

fn is_sha256(text: &str) -> bool {
    text.len() == 64 && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

type Checked<T> = Result<T, String>;

struct Object(Map<String, Value>);

impl Object {
    fn parse(body: &[u8], allowed: &[&str]) -> Checked<Object> {
        let value: Value = serde_json::from_slice(body).map_err(|_| "body must be a JSON object".to_string())?;
        let Value::Object(map) = value else { return Err("body must be a JSON object".into()) };
        if let Some(extra) = map.keys().find(|key| !allowed.contains(&key.as_str())) {
            return Err(format!("unknown field {extra}"));
        }
        Ok(Object(map))
    }

    fn has(&self, key: &str) -> bool {
        self.0.get(key).is_some_and(|value| !value.is_null())
    }

    fn text(&self, key: &str) -> Checked<&str> {
        self.0.get(key).and_then(Value::as_str).ok_or_else(|| format!("{key} must be a string"))
    }

    fn id(&self, key: &str) -> Checked<String> {
        let text = self.text(key)?;
        if is_id(text) { Ok(text.to_string()) } else { Err(format!("{key} is not a valid id")) }
    }

    fn int(&self, key: &str, low: u64, high: u64) -> Checked<u64> {
        let number = self.0.get(key).and_then(Value::as_u64).ok_or_else(|| format!("{key} must be a whole number"))?;
        if (low..=high).contains(&number) { Ok(number) } else { Err(format!("{key} is out of range")) }
    }

    fn choice<'a>(&'a self, key: &str, options: &[&'a str]) -> Checked<&'a str> {
        let text = self.text(key)?;
        options.iter().copied().find(|option| *option == text).ok_or_else(|| format!("{key} is not an allowed value"))
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CreateRequest {
    pub command_id: String,
    pub name: String,
    pub kind: Kind,
    pub cpu: u32,
    pub ram_mb: u64,
    pub disk_gb: u64,
    pub gpu_mode: GpuMode,
    pub image: Option<String>,
}

impl CreateRequest {
    pub fn parse(body: &[u8]) -> Checked<CreateRequest> {
        let object = Object::parse(body, &["command_id", "name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode", "image"])?;
        let kind = if object.choice("kind", &["vm", "container"])? == "vm" { Kind::Vm } else { Kind::Container };
        Ok(CreateRequest {
            command_id: object.id("command_id")?,
            name: object.id("name")?,
            kind,
            cpu: object.int("cpu", 1, 64)? as u32,
            ram_mb: object.int("ram_mb", 512, 1_048_576)?,
            disk_gb: object.int("disk_gb", 1, 100_000)?,
            gpu_mode: Self::gpu_mode(&object)?,
            image: Self::image(&object)?,
        })
    }

    fn gpu_mode(object: &Object) -> Checked<GpuMode> {
        if !object.has("gpu_mode") {
            return Ok(GpuMode::None);
        }
        Ok(match object.choice("gpu_mode", &["none", "container", "passthrough"])? {
            "container" => GpuMode::Container,
            "passthrough" => GpuMode::Passthrough,
            _ => GpuMode::None,
        })
    }

    fn image(object: &Object) -> Checked<Option<String>> {
        if !object.has("image") {
            return Ok(None);
        }
        let text = object.text("image")?;
        if is_image(text) { Ok(Some(text.to_string())) } else { Err("image has a bad shape".into()) }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct BundleRequest {
    pub command_id: String,
    pub version: String,
    pub sha256: String,
    pub workload_id: Option<String>,
}

impl BundleRequest {
    pub fn parse(body: &[u8]) -> Checked<BundleRequest> {
        let object = Object::parse(body, &["command_id", "version", "sha256", "workload_id"])?;
        let version = object.text("version")?;
        if !is_semver(version) {
            return Err("version must look like 1.2.3".into());
        }
        let sha256 = object.text("sha256")?;
        if !is_sha256(sha256) {
            return Err("sha256 must be 64 lowercase hex characters".into());
        }
        Ok(BundleRequest {
            command_id: object.id("command_id")?,
            version: version.to_string(),
            sha256: sha256.to_string(),
            workload_id: if object.has("workload_id") { Some(object.id("workload_id")?) } else { None },
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn create(change: impl FnOnce(&mut Value)) -> Checked<CreateRequest> {
        let mut body = json!({"command_id": "c-1", "name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10});
        change(&mut body);
        CreateRequest::parse(body.to_string().as_bytes())
    }

    #[test]
    fn a_good_create_body_is_read_with_defaults() {
        let request = create(|_| {}).unwrap();
        assert_eq!((request.kind, request.gpu_mode, request.image), (Kind::Vm, GpuMode::None, None));
        assert_eq!(create(|b| { b["image"] = json!("ubuntu:24.04"); b["gpu_mode"] = json!("container"); }).unwrap().image.as_deref(), Some("ubuntu:24.04"));
    }

    #[test]
    fn every_bad_field_is_refused() {
        type Change = Box<dyn Fn(&mut Value)>;
        let bad: Vec<(&str, Change)> = vec![
            ("name upper", Box::new(|b| b["name"] = json!("Bad"))), ("name shell", Box::new(|b| b["name"] = json!("$(reboot)"))),
            ("name sql", Box::new(|b| b["name"] = json!("x'; DROP--"))), ("kind", Box::new(|b| b["kind"] = json!("metal"))),
            ("cpu 0", Box::new(|b| b["cpu"] = json!(0))), ("cpu 65", Box::new(|b| b["cpu"] = json!(65))), ("cpu string", Box::new(|b| b["cpu"] = json!("2"))),
            ("cpu float", Box::new(|b| b["cpu"] = json!(1.5))), ("cpu bool", Box::new(|b| b["cpu"] = json!(true))), ("ram low", Box::new(|b| b["ram_mb"] = json!(511))),
            ("disk 0", Box::new(|b| b["disk_gb"] = json!(0))), ("disk big", Box::new(|b| b["disk_gb"] = json!(100_001))), ("negative", Box::new(|b| b["disk_gb"] = json!(-5))),
            ("gpu mode", Box::new(|b| b["gpu_mode"] = json!("all"))), ("image flag", Box::new(|b| b["image"] = json!("--privileged"))), ("image space", Box::new(|b| b["image"] = json!("a b"))),
            ("command id", Box::new(|b| b["command_id"] = json!("../x"))), ("extra", Box::new(|b| b["surprise"] = json!(1))), ("missing", Box::new(|b| { b.as_object_mut().unwrap().remove("name"); })),
        ];
        for (label, change) in bad {
            assert!(create(change).is_err(), "{label}");
        }
        for raw in ["", "{", "null", "[]", "\"text\""] {
            assert!(CreateRequest::parse(raw.as_bytes()).is_err(), "{raw}");
        }
    }

    #[test]
    fn bundle_requests_are_strict_too() {
        let sha = "a".repeat(64);
        let good = |extra: Value| {
            let mut body = json!({"command_id": "c", "version": "1.2.3", "sha256": sha});
            body.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
            BundleRequest::parse(body.to_string().as_bytes())
        };
        assert!(good(json!({})).unwrap().workload_id.is_none());
        for change in [json!({"version": "1.2"}), json!({"version": "v1.2.3"}), json!({"sha256": "short"}), json!({"sha256": "G".repeat(64)}), json!({"workload_id": "Bad Id"}), json!({"x": 1})] {
            assert!(good(change.clone()).is_err(), "{change}");
        }
    }

    #[test]
    fn ids_and_versions() {
        assert!(is_id("a") && is_id("w-abc") && !is_id("A") && !is_id("-a") && !is_id(&"a".repeat(64)) && !is_id(""));
        assert!(is_semver("1.2.3") && !is_semver("1.2") && !is_semver("1.2.3; x"));
    }
}
