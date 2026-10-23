//! Requests are read strictly: unknown fields are refused and every field is checked for type, size and shape.
use crate::cpu::CpuFlag;
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

fn is_cpu_model(text: &str) -> bool {
    static PATTERN: OnceLock<Regex> = OnceLock::new();
    PATTERN.get_or_init(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$").unwrap()).is_match(text)
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

    /// The key is in the body, even as null. The CPU settings use it: for them null is a wrong value, not a field left out.
    fn sent(&self, key: &str) -> bool {
        self.0.contains_key(key)
    }

    /// A nested object whose keys must all be in `allowed`.
    fn object(&self, key: &str, allowed: &[&str]) -> Checked<Object> {
        let map = self.0.get(key).and_then(Value::as_object).ok_or_else(|| format!("{key} must be an object"))?;
        if map.keys().any(|inner| !allowed.contains(&inner.as_str())) {
            return Err(format!("{key} may only hold {}", allowed.join(" and ")));
        }
        Ok(Object(map.clone()))
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
    /// A GPU memory limit in GB, only for a container that shares the GPU.
    pub gpu_memory_gb: Option<u32>,
    /// How many sockets a VM's CPUs are spread over, as asked. None or 1: the engine's own layout, as before.
    pub cpu_sockets: Option<u32>,
    /// The CPU model a VM sees, as asked. None or `host`: the machine's own CPU, as before.
    pub cpu_type: Option<String>,
    /// The CPU flags a VM asked to have on (true) or off, nested-virt first. Empty: what the CPU model gives.
    pub cpu_flags: Vec<(CpuFlag, bool)>,
    /// A hard cap on a container's CPU time, in percent of one core (150 is one and a half cores).
    pub cpu_limit_percent: Option<u32>,
}

const MAX_GPU_MEMORY_GB: u64 = 1024;
const MAX_CPU_SOCKETS: u64 = 8;
const MIN_CPU_LIMIT_PERCENT: u64 = 10;
const MAX_CPU_LIMIT_PERCENT: u64 = 6400;
/// A cap of 100 percent is one whole core.
const PERCENT_PER_CPU: u64 = 100;

impl CreateRequest {
    pub fn parse(body: &[u8]) -> Checked<CreateRequest> {
        let object = Object::parse(body, &["command_id", "name", "kind", "cpu", "ram_mb", "disk_gb", "gpu_mode", "image", "gpu_memory_gb", "cpu_sockets", "cpu_type", "cpu_flags", "cpu_limit_percent"])?;
        let kind = if object.choice("kind", &["vm", "container"])? == "vm" { Kind::Vm } else { Kind::Container };
        let gpu_mode = Self::gpu_mode(&object)?;
        let cpu = object.int("cpu", 1, 64)? as u32;
        Ok(CreateRequest {
            command_id: object.id("command_id")?,
            name: object.id("name")?,
            kind,
            cpu,
            ram_mb: object.int("ram_mb", 512, 1_048_576)?,
            disk_gb: object.int("disk_gb", 1, 100_000)?,
            gpu_mode,
            image: Self::image(&object)?,
            gpu_memory_gb: Self::gpu_memory_gb(&object, kind, gpu_mode)?,
            cpu_sockets: Self::cpu_sockets(&object, kind, cpu)?,
            cpu_type: Self::cpu_type(&object, kind)?,
            cpu_flags: Self::cpu_flags(&object, kind)?,
            cpu_limit_percent: Self::cpu_limit_percent(&object, kind, cpu)?,
        })
    }

    /// 1 to 8 sockets, and `cpu` must spread evenly over them. Kept as sent: even 1 needs a machine that offers sockets (the service checks that).
    fn cpu_sockets(object: &Object, kind: Kind, cpu: u32) -> Checked<Option<u32>> {
        if !object.sent("cpu_sockets") {
            return Ok(None);
        }
        if kind != Kind::Vm {
            return Err("cpu_sockets is only allowed for a vm".into());
        }
        let sockets = object.int("cpu_sockets", 1, MAX_CPU_SOCKETS)? as u32;
        if !cpu.is_multiple_of(sockets) {
            return Err("cpu must be a multiple of cpu_sockets".into());
        }
        Ok(Some(sockets))
    }

    /// A plain model name, kept as sent. Whether this machine offers it is the service's check.
    fn cpu_type(object: &Object, kind: Kind) -> Checked<Option<String>> {
        if !object.sent("cpu_type") {
            return Ok(None);
        }
        if kind != Kind::Vm {
            return Err("cpu_type is only allowed for a vm".into());
        }
        let text = object.text("cpu_type")?;
        if !is_cpu_model(text) {
            return Err("cpu_type has a bad shape".into());
        }
        Ok(Some(text.to_string()))
    }

    /// An object of `nested-virt` and `aes`, each `on` or `off`, with at least one of them.
    fn cpu_flags(object: &Object, kind: Kind) -> Checked<Vec<(CpuFlag, bool)>> {
        if !object.sent("cpu_flags") {
            return Ok(Vec::new());
        }
        if kind != Kind::Vm {
            return Err("cpu_flags is only allowed for a vm".into());
        }
        let flags = object.object("cpu_flags", &CpuFlag::ALL.map(CpuFlag::name))?;
        if flags.0.is_empty() {
            return Err("cpu_flags needs at least one flag".into());
        }
        let switch = |flag: CpuFlag| flags.choice(flag.name(), &["on", "off"]).map(|word| (flag, word == "on")).map_err(|_| "cpu_flags values must be on or off".to_string());
        CpuFlag::ALL.into_iter().filter(|flag| flags.sent(flag.name())).map(switch).collect()
    }

    /// 10 to 6400 percent of one core, and at most `cpu` x 100.
    fn cpu_limit_percent(object: &Object, kind: Kind, cpu: u32) -> Checked<Option<u32>> {
        if !object.sent("cpu_limit_percent") {
            return Ok(None);
        }
        if kind != Kind::Container {
            return Err("cpu_limit_percent is only allowed for a container".into());
        }
        let percent = object.int("cpu_limit_percent", MIN_CPU_LIMIT_PERCENT, MAX_CPU_LIMIT_PERCENT)?;
        if percent > u64::from(cpu) * PERCENT_PER_CPU {
            return Err("cpu_limit_percent can be at most cpu x 100".into());
        }
        Ok(Some(percent as u32))
    }

    fn gpu_memory_gb(object: &Object, kind: Kind, gpu_mode: GpuMode) -> Checked<Option<u32>> {
        if !object.has("gpu_memory_gb") {
            return Ok(None);
        }
        if kind != Kind::Container || gpu_mode != GpuMode::Container {
            return Err("gpu_memory_gb is only allowed for a container with gpu_mode container".into());
        }
        Ok(Some(object.int("gpu_memory_gb", 1, MAX_GPU_MEMORY_GB)? as u32))
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

/// Turning the chat off on the machine (no workload_id) or in one workload.
#[derive(Clone, Debug, PartialEq)]
pub struct BundleUninstallRequest {
    pub command_id: String,
    pub workload_id: Option<String>,
}

impl BundleUninstallRequest {
    pub fn parse(body: &[u8]) -> Checked<BundleUninstallRequest> {
        let object = Object::parse(body, &["command_id", "workload_id"])?;
        Ok(BundleUninstallRequest {
            command_id: object.id("command_id")?,
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

    fn limited(change: impl FnOnce(&mut Value)) -> Checked<CreateRequest> {
        create(|body| {
            body["kind"] = json!("container");
            body["gpu_mode"] = json!("container");
            body["gpu_memory_gb"] = json!(4);
            change(body);
        })
    }

    #[test]
    fn a_gpu_memory_limit_is_read_for_a_gpu_container_only() {
        assert_eq!(limited(|_| {}).unwrap().gpu_memory_gb, Some(4));
        assert_eq!(limited(|b| b["gpu_memory_gb"] = json!(1)).unwrap().gpu_memory_gb, Some(1));
        assert_eq!(limited(|b| b["gpu_memory_gb"] = json!(1024)).unwrap().gpu_memory_gb, Some(1024));
        assert_eq!(limited(|b| b["gpu_memory_gb"] = Value::Null).unwrap().gpu_memory_gb, None);
        assert_eq!(limited(|b| { b.as_object_mut().unwrap().remove("gpu_memory_gb"); }).unwrap().gpu_memory_gb, None);
        assert_eq!(create(|_| {}).unwrap().gpu_memory_gb, None);
    }

    #[test]
    fn a_gpu_memory_limit_is_refused_when_it_does_not_fit() {
        let refused: [(&str, Checked<CreateRequest>); 8] = [
            ("zero", limited(|b| b["gpu_memory_gb"] = json!(0))),
            ("too big", limited(|b| b["gpu_memory_gb"] = json!(1025))),
            ("negative", limited(|b| b["gpu_memory_gb"] = json!(-1))),
            ("fraction", limited(|b| b["gpu_memory_gb"] = json!(1.5))),
            ("text", limited(|b| b["gpu_memory_gb"] = json!("4"))),
            ("vm", limited(|b| b["kind"] = json!("vm"))),
            ("no gpu", limited(|b| b["gpu_mode"] = json!("none"))),
            ("passthrough", limited(|b| b["gpu_mode"] = json!("passthrough"))),
        ];
        for (label, result) in refused {
            let message = result.expect_err(label);
            assert!(message.contains("gpu_memory_gb"), "{label}: {message}");
        }
        let echoed = limited(|b| b["gpu_memory_gb"] = json!("secret-value")).unwrap_err();
        assert!(!echoed.contains("secret-value"));
    }

    /// A VM with 4 CPUs and every CPU setting a VM can have.
    fn processors(change: impl FnOnce(&mut Value)) -> Checked<CreateRequest> {
        create(|body| {
            body["cpu"] = json!(4);
            body["cpu_sockets"] = json!(2);
            body["cpu_type"] = json!("EPYC-Genoa");
            body["cpu_flags"] = json!({"nested-virt": "on", "aes": "off"});
            change(body);
        })
    }

    /// A container with 2 CPUs capped at one and a half cores.
    fn capped(change: impl FnOnce(&mut Value)) -> Checked<CreateRequest> {
        create(|body| {
            body["kind"] = json!("container");
            body["cpu_limit_percent"] = json!(150);
            change(body);
        })
    }

    #[test]
    fn the_cpu_settings_are_read_for_their_kind() {
        let vm = processors(|_| {}).unwrap();
        assert_eq!((vm.cpu_sockets, vm.cpu_type.as_deref()), (Some(2), Some("EPYC-Genoa")));
        assert_eq!(vm.cpu_flags, [(CpuFlag::NestedVirt, true), (CpuFlag::Aes, false)]);
        let aes_first = processors(|b| b["cpu_flags"] = json!({"aes": "on", "nested-virt": "off"})).unwrap();
        assert_eq!(aes_first.cpu_flags, [(CpuFlag::NestedVirt, false), (CpuFlag::Aes, true)], "always in the same order");
        assert_eq!(processors(|b| b["cpu_flags"] = json!({"aes": "on"})).unwrap().cpu_flags, [(CpuFlag::Aes, true)]);
        assert_eq!(processors(|b| { b["cpu"] = json!(64); b["cpu_sockets"] = json!(8); }).unwrap().cpu_sockets, Some(8));
        assert_eq!(capped(|_| {}).unwrap().cpu_limit_percent, Some(150));
        assert_eq!(capped(|b| b["cpu_limit_percent"] = json!(200)).unwrap().cpu_limit_percent, Some(200), "exactly cpu x 100");
        assert_eq!(capped(|b| { b["cpu"] = json!(64); b["cpu_limit_percent"] = json!(6400); }).unwrap().cpu_limit_percent, Some(6400));
        assert_eq!(capped(|b| { b["cpu"] = json!(1); b["cpu_limit_percent"] = json!(10); }).unwrap().cpu_limit_percent, Some(10));
        let plain = create(|_| {}).unwrap();
        assert_eq!((plain.cpu_sockets, plain.cpu_type, plain.cpu_flags, plain.cpu_limit_percent), (None, None, vec![], None));
    }

    #[test]
    fn one_socket_and_the_host_model_are_kept_as_sent() {
        let same = processors(|b| { b["cpu_sockets"] = json!(1); b["cpu_type"] = json!("host"); b.as_object_mut().unwrap().remove("cpu_flags"); }).unwrap();
        assert_eq!((same.cpu_sockets, same.cpu_type.as_deref(), same.cpu_flags.len()), (Some(1), Some("host"), 0), "the service decides whether this machine offers them");
        assert_eq!(processors(|b| { b["cpu"] = json!(3); b["cpu_sockets"] = json!(1); }).unwrap().cpu_sockets, Some(1), "any cpu fits one socket");
    }

    #[test]
    fn the_cpu_settings_are_refused_when_they_do_not_fit() {
        let refused: Vec<(&str, Checked<CreateRequest>)> = vec![
            ("sockets on a container", capped(|b| b["cpu_sockets"] = json!(2))), ("type on a container", capped(|b| b["cpu_type"] = json!("host"))),
            ("flags on a container", capped(|b| b["cpu_flags"] = json!({"aes": "on"}))), ("limit on a vm", processors(|b| b["cpu_limit_percent"] = json!(100))),
            ("no sockets", processors(|b| b["cpu_sockets"] = json!(0))), ("nine sockets", processors(|b| { b["cpu"] = json!(64); b["cpu_sockets"] = json!(9); })),
            ("half a socket", processors(|b| b["cpu_sockets"] = json!(1.5))), ("sockets text", processors(|b| b["cpu_sockets"] = json!("2"))),
            ("sockets null", processors(|b| b["cpu_sockets"] = Value::Null)), ("uneven", processors(|b| b["cpu"] = json!(3))),
            ("more sockets than cpus", processors(|b| b["cpu"] = json!(1))), ("type empty", processors(|b| b["cpu_type"] = json!(""))),
            ("type flag", processors(|b| b["cpu_type"] = json!("-host"))), ("type space", processors(|b| b["cpu_type"] = json!("EPYC Genoa"))),
            ("type comma", processors(|b| b["cpu_type"] = json!("host,+vmx"))), ("type shell", processors(|b| b["cpu_type"] = json!("host;reboot"))),
            ("type line", processors(|b| b["cpu_type"] = json!("host\n"))), ("type long", processors(|b| b["cpu_type"] = json!("x".repeat(41)))),
            ("type number", processors(|b| b["cpu_type"] = json!(5))), ("type null", processors(|b| b["cpu_type"] = Value::Null)),
            ("flags empty", processors(|b| b["cpu_flags"] = json!({}))), ("flags list", processors(|b| b["cpu_flags"] = json!(["aes"]))),
            ("flags text", processors(|b| b["cpu_flags"] = json!("aes"))), ("flags null", processors(|b| b["cpu_flags"] = Value::Null)),
            ("flag vmx", processors(|b| b["cpu_flags"] = json!({"vmx": "on"}))), ("flag yes", processors(|b| b["cpu_flags"] = json!({"aes": "yes"}))),
            ("flag true", processors(|b| b["cpu_flags"] = json!({"aes": true}))), ("flag null", processors(|b| b["cpu_flags"] = json!({"aes": null}))),
            ("limit low", capped(|b| b["cpu_limit_percent"] = json!(9))), ("limit high", capped(|b| { b["cpu"] = json!(64); b["cpu_limit_percent"] = json!(6401); })),
            ("over cpu x 100", capped(|b| b["cpu_limit_percent"] = json!(201))), ("limit fraction", capped(|b| b["cpu_limit_percent"] = json!(150.5))),
            ("limit text", capped(|b| b["cpu_limit_percent"] = json!("150"))), ("limit bool", capped(|b| b["cpu_limit_percent"] = json!(true))),
            ("limit null", capped(|b| b["cpu_limit_percent"] = Value::Null)),
        ];
        for (label, result) in refused {
            let message = result.expect_err(label);
            assert!(message.contains("cpu"), "{label}: {message}");
        }
        let echoed = processors(|b| b["cpu_type"] = json!("secret value")).unwrap_err();
        assert!(!echoed.contains("secret"));
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
    fn uninstall_requests_are_strict() {
        let good = |extra: Value| {
            let mut body = json!({"command_id": "c"});
            body.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
            BundleUninstallRequest::parse(body.to_string().as_bytes())
        };
        assert!(good(json!({})).unwrap().workload_id.is_none());
        assert_eq!(good(json!({"workload_id": "w-1"})).unwrap().workload_id.as_deref(), Some("w-1"));
        let hostile = ["'; DROP TABLE x;--", "<script>alert(1)</script>", "$(reboot)", "`id`", "../../etc/passwd", "a b", "--privileged", "", "line\nbreak"];
        for text in hostile {
            assert!(good(json!({"workload_id": text})).is_err(), "workload_id {text:?}");
            assert!(BundleUninstallRequest::parse(json!({"command_id": text}).to_string().as_bytes()).is_err(), "command_id {text:?}");
        }
        for change in [json!({"surprise": 1}), json!({"path": "/bin/sh"}), json!({"version": "1.2.3"}), json!({"command_id": 5}), json!({"workload_id": ["w"]})] {
            assert!(good(change.clone()).is_err(), "{change}");
        }
        for raw in ["", "{", "null", "[]", "\"text\"", "{}"] {
            assert!(BundleUninstallRequest::parse(raw.as_bytes()).is_err(), "{raw}");
        }
    }

    #[test]
    fn ids_and_versions() {
        assert!(is_id("a") && is_id("w-abc") && !is_id("A") && !is_id("-a") && !is_id(&"a".repeat(64)) && !is_id(""));
        assert!(is_semver("1.2.3") && !is_semver("1.2") && !is_semver("1.2.3; x"));
    }
}
