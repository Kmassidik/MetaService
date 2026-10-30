//! What `join-share-root` does as root, after `root_args::parse` accepted the
//! arguments. The hub config is validated and copied into a root-only folder
//! before wg-quick sees it, so the user-writable original cannot be swapped
//! for one with command keys after the check.
use crate::constants::{PF_MARKER_PREFIX, ROOT_RUN_DIR};
use crate::firewall;
use crate::peers::hubconf;
use crate::peers::Net;
use crate::root_args::{RootCommand, RootRequest};
use std::fs;
use std::io::Write;
use std::net::Ipv4Addr;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const TOOL_DIRS: [&str; 4] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/sbin"];
/// wg-quick is a Homebrew bash script on macOS and needs /opt/homebrew/bin first.
const CHILD_PATH: &str = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
const WG_QUICK_IFACE_MARK: &str = "Interface for ";

pub fn execute(request: RootRequest) -> Result<String, String> {
    let RootRequest { command, wg_name, anchor, parent_port } = request;
    match command {
        RootCommand::Up { conf } => up(&conf, &wg_name),
        RootCommand::Down => run("wg-quick", &["down", &installed_conf(&wg_name).to_string_lossy()], None),
        RootCommand::AddPeer { public_key, address } => add_peer(&wg_name, &public_key, address),
        RootCommand::RemovePeer { public_key } => run("wg", &["set", &wg_name, "peer", &public_key, "remove"], None),
        RootCommand::PfLoad { iface } => pf_load(&wg_name, &anchor, parent_port, iface),
        RootCommand::PfUnload => pf_unload(&wg_name, &anchor),
        RootCommand::Show => show(&wg_name),
    }
}

fn installed_conf(wg_name: &str) -> PathBuf {
    Path::new(ROOT_RUN_DIR).join(format!("{wg_name}.conf"))
}

fn run(tool: &str, args: &[&str], stdin: Option<&str>) -> Result<String, String> {
    run_captured(tool, args, stdin).map(|(stdout, _)| stdout)
}

/// Stdout and stderr together (wg-quick reports its progress on stderr).
fn run_all_output(tool: &str, args: &[&str]) -> Result<String, String> {
    run_captured(tool, args, None).map(|(out, err)| format!("{out}\n{err}"))
}

fn run_captured(tool: &str, args: &[&str], stdin: Option<&str>) -> Result<(String, String), String> {
    let program = TOOL_DIRS
        .iter()
        .map(|d| Path::new(d).join(tool))
        .find(|p| p.exists())
        .ok_or_else(|| format!("{tool} not found"))?;
    let mut child = Command::new(program)
        .args(args)
        .env_clear()
        .env("PATH", CHILD_PATH)
        .stdin(if stdin.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{tool}: {e}"))?;
    if let Some(input) = stdin {
        child.stdin.take().ok_or("no stdin")?.write_all(input.as_bytes()).map_err(|e| format!("{tool}: {e}"))?;
    }
    let out = child.wait_with_output().map_err(|e| format!("{tool}: {e}"))?;
    if !out.status.success() {
        return Err(format!("{tool} failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
    }
    Ok((String::from_utf8_lossy(&out.stdout).trim().to_string(), String::from_utf8_lossy(&out.stderr).trim().to_string()))
}

fn up(source: &Path, wg_name: &str) -> Result<String, String> {
    let text = fs::read_to_string(source).map_err(|e| format!("cannot read config: {e}"))?;
    hubconf::validate(&text)?;
    fs::DirBuilder::new().recursive(true).mode(0o700).create(ROOT_RUN_DIR).map_err(|e| format!("run dir: {e}"))?;
    let target = installed_conf(wg_name);
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&target)
        .map_err(|e| format!("cannot write {}: {e}", target.display()))?;
    file.write_all(text.as_bytes()).map_err(|e| format!("cannot write config: {e}"))?;
    let output = run_all_output("wg-quick", &["up", &target.to_string_lossy()])?;
    Ok(iface_from_wg_quick(&output, wg_name))
}

/// wg-quick prints `[+] Interface for <name> is utunN`; the name file is root-only.
pub fn iface_from_wg_quick(output: &str, wg_name: &str) -> String {
    output
        .lines()
        .filter_map(|l| l.split_once(WG_QUICK_IFACE_MARK))
        .filter_map(|(_, rest)| rest.split_once(" is "))
        .map(|(_, iface)| iface.trim().to_string())
        .find(|iface| crate::root_args::is_iface_name(iface))
        .unwrap_or_else(|| wg_name.to_string())
}

/// The network comes from the validated copy, so a caller cannot choose it.
fn installed_net(wg_name: &str) -> Result<Net, String> {
    let text = fs::read_to_string(installed_conf(wg_name)).map_err(|_| "hub interface was never brought up".to_string())?;
    let address = text
        .lines()
        .find_map(|l| l.trim().strip_prefix("Address").and_then(|r| r.trim().strip_prefix('=')))
        .ok_or("installed config has no Address")?;
    Net::parse(address.trim())
}

fn add_peer(wg_name: &str, public_key: &str, address: Ipv4Addr) -> Result<String, String> {
    let net = installed_net(wg_name)?;
    if !net.is_peer_address(address) {
        return Err(format!("{address} is not a peer address of {}", net.cidr()));
    }
    run("wg", &["set", wg_name, "peer", public_key, "allowed-ips", &format!("{address}/32")], None)
}

fn marker(wg_name: &str) -> PathBuf {
    Path::new(ROOT_RUN_DIR).join(format!("{PF_MARKER_PREFIX}{wg_name}"))
}

/// Turns pf on only if it is off (remembering that), then loads our one anchor.
fn pf_load(wg_name: &str, anchor: &str, parent_port: u16, iface: Option<String>) -> Result<String, String> {
    let rules = firewall::anchor_rules(&iface.unwrap_or_else(|| wg_name.to_string()), &installed_net(wg_name)?, parent_port);
    if run("pfctl", &["-s", "info"], None)?.contains("Status: Disabled") {
        run("pfctl", &["-e"], None)?;
        fs::write(marker(wg_name), "").map_err(|e| format!("cannot write pf marker: {e}"))?;
    }
    run("pfctl", &["-a", anchor, "-f", "-"], Some(&rules))
}

fn pf_unload(wg_name: &str, anchor: &str) -> Result<String, String> {
    run("pfctl", &["-a", anchor, "-F", "all"], None)?;
    if !marker(wg_name).exists() {
        return Ok(String::new());
    }
    run("pfctl", &["-d"], None)?;
    fs::remove_file(marker(wg_name)).map_err(|e| format!("cannot remove pf marker: {e}"))?;
    Ok(String::new())
}

/// `wg show latest-handshakes` lines become the JSON the hub parses.
fn show(wg_name: &str) -> Result<String, String> {
    let text = run("wg", &["show", wg_name, "latest-handshakes"], None)?;
    let peers: Vec<serde_json::Value> = text
        .lines()
        .filter_map(|line| line.split_once('\t'))
        .map(|(key, at)| serde_json::json!({ "public_key": key, "last_handshake": at.trim().parse::<i64>().unwrap_or(0) }))
        .collect();
    Ok(serde_json::Value::Array(peers).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_interface_from_wg_quick_output() {
        let out = "[#] wireguard-go utun\n[+] Interface for wg-metaservice is utun9\n[#] ifconfig";
        assert_eq!(iface_from_wg_quick(out, "wg-metaservice"), "utun9");
    }

    #[test]
    fn falls_back_to_logical_name() {
        assert_eq!(iface_from_wg_quick("nothing useful", "wg-x"), "wg-x");
        assert_eq!(iface_from_wg_quick("Interface for x is evil;rm", "wg-x"), "wg-x");
    }
}
