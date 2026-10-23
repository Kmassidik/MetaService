//! What `incus query /1.0` says that decides what a VM's processors can be given: the QEMU version VMs run on, and whether `limits.cpu` takes a topology.
use super::args;
use serde_json::Value;

/// The API extension that lets a VM's `limits.cpu` be `sockets=2,cores=4,threads=1` (Incus 7.1, and 7.0.1 LTS).
const TOPOLOGY_EXTENSION: &str = "instance_limits_cpu_topology";
/// The instance driver VMs run on, as the server names it.
const QEMU_DRIVER: &str = "qemu";

/// What the server says. A version it does not plainly give is None: a version is never guessed.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ServerCpu {
    /// The QEMU version VMs run on, as (major, minor).
    pub qemu: Option<(u32, u32)>,
    /// `limits.cpu` takes a topology.
    pub topology: bool,
}

/// The arguments that ask the server about itself.
pub fn query_arguments() -> Vec<String> {
    args(&["query", "/1.0"])
}

/// Reads the server's answer. None when it is not the JSON of a server at all.
pub fn parse_server(text: &str) -> Option<ServerCpu> {
    let server: Value = serde_json::from_str(text).ok()?;
    let extensions = server.get("api_extensions")?.as_array()?;
    let environment = server.get("environment")?;
    let text_of = |key: &str| environment.get(key).and_then(Value::as_str).unwrap_or_default();
    Some(ServerCpu {
        qemu: qemu_version(text_of("driver"), text_of("driver_version")),
        topology: extensions.iter().any(|name| name.as_str() == Some(TOPOLOGY_EXTENSION)),
    })
}

/// The QEMU version out of `driver` and `driver_version`, which name the instance drivers and their versions in the same order, like "lxc | qemu" and
/// "6.0.4 | 9.2.4" (Incus walks a map, so the order can change). Lists of different lengths, or a version that is not plainly numbers, give None.
pub fn qemu_version(drivers: &str, versions: &str) -> Option<(u32, u32)> {
    let drivers: Vec<&str> = drivers.split('|').map(str::trim).collect();
    let versions: Vec<&str> = versions.split('|').map(str::trim).collect();
    if drivers.len() != versions.len() {
        return None;
    }
    let (_, version) = drivers.iter().zip(&versions).find(|(driver, _)| **driver == QEMU_DRIVER)?;
    let mut parts = version.split('.').map(number);
    Some((parts.next()??, parts.next()??))
}

/// A short run of digits as a number. `+1`, `1a` and an empty part are not numbers.
fn number(text: &str) -> Option<u32> {
    (!text.is_empty() && text.len() <= 4 && text.bytes().all(|b| b.is_ascii_digit())).then(|| text.parse().ok()).flatten()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn server(extensions: &[&str], driver: &str, driver_version: &str) -> String {
        serde_json::json!({"api_extensions": extensions, "api_version": "1.0", "auth": "trusted",
            "environment": {"architectures": ["x86_64", "i686"], "driver": driver, "driver_version": driver_version, "server": "incus", "server_version": "7.1"}}).to_string()
    }

    #[test]
    fn the_qemu_version_is_read_at_the_position_of_the_qemu_driver() {
        assert_eq!(qemu_version("lxc | qemu", "6.0.4 | 9.2.4"), Some((9, 2)));
        assert_eq!(qemu_version("qemu | lxc", "9.2.4 | 6.0.4"), Some((9, 2)), "Incus can list the drivers either way round");
        assert_eq!(qemu_version("qemu", "10.1.50"), Some((10, 1)), "a development build counts as the release before it");
        assert_eq!(qemu_version("lxc | qemu", "6.0.4 | 8.2.2-dirty"), Some((8, 2)));
    }

    #[test]
    fn a_version_that_is_not_plainly_given_is_none() {
        for (drivers, versions) in [("lxc", "6.0.4"), ("lxc | qemu", "6.0.4"), ("lxc | qemu", "6.0.4 | 9.2.4 | 1.0"), ("lxc | qemu", "6.0.4 | unknown"),
            ("lxc | qemu", "6.0.4 | 9"), ("lxc | qemu", "6.0.4 | +9.2"), ("lxc | qemu", "6.0.4 | 9.x"), ("", ""), ("lxc | qemu", "6.0.4 | 99999.1")] {
            assert_eq!(qemu_version(drivers, versions), None, "{drivers} / {versions}");
        }
    }

    #[test]
    fn sockets_need_the_topology_extension() {
        let with = parse_server(&server(&["instances", "instance_limits_cpu_topology", "instance_nbd"], "lxc | qemu", "6.0.4 | 9.2.4")).unwrap();
        assert_eq!(with, ServerCpu { qemu: Some((9, 2)), topology: true });
        let without = parse_server(&server(&["instances", "instance_limits_cpu"], "qemu | lxc", "8.2.2 | 6.0.0")).unwrap();
        assert_eq!(without, ServerCpu { qemu: Some((8, 2)), topology: false });
        assert_eq!(parse_server(&server(&[], "lxc", "6.0.4")).unwrap(), ServerCpu { qemu: None, topology: false }, "containers only");
    }

    #[test]
    fn an_answer_that_is_not_a_server_is_none() {
        for junk in ["", "null", "[]", "{}", r#"{"api_extensions": "x"}"#, r#"{"api_extensions": []}"#, "Error: not found", r#"[{"name":"ms-w-1"}]"#] {
            assert_eq!(parse_server(junk), None, "{junk}");
        }
        let odd = r#"{"api_extensions": [7, null, "instance_limits_cpu_topology"], "environment": {"driver": 5}}"#;
        assert_eq!(parse_server(odd), Some(ServerCpu { qemu: None, topology: true }));
    }
}
