//! `metaservice-agent enroll`: trade a one-time enrollment token for this machine's two permanent tokens, and save them (mode 600).
use crate::config::Config;
use crate::files::write_private;
use crate::validate::is_id;
use serde_json::{json, Value};
use std::time::Duration;

/// A Root address: http(s), a host, no credentials, no query.
pub fn valid_root(text: &str) -> Result<String, String> {
    let rest = text.strip_prefix("http://").or_else(|| text.strip_prefix("https://")).ok_or("--root must be an http(s) address such as http://192.168.100.40:9100")?;
    let host = rest.split('/').next().unwrap_or("");
    if host.is_empty() || host.contains('@') || text.contains('?') || text.contains('#') {
        return Err("--root must be an http(s) address with a host, no credentials and no query".into());
    }
    Ok(text.trim_end_matches('/').to_string())
}

pub fn run(config: &Config, root: &str, name: &str, token_file: Option<&str>) -> Result<(), String> {
    if !is_id(name) {
        return Err("--name must use lowercase letters, numbers and dashes".into());
    }
    let base = valid_root(root)?;
    let token = read_enrollment_token(token_file)?;
    let reply = ureq::post(&format!("{base}/v1/agents/enroll")).timeout(Duration::from_secs(15)).set("Content-Type", "application/json")
        .send_string(&json!({"enrollment_token": token, "name": name}).to_string())
        .map_err(|_| "the Root refused the enrollment (wrong, used or expired token, or wrong address)".to_string())?;
    let body: Value = serde_json::from_reader(reply.into_reader()).map_err(|_| "the Root's answer was not understood".to_string())?;
    let (machine, command) = (body["machine_token"].as_str(), body["command_token"].as_str());
    let (Some(machine), Some(command)) = (machine, command) else { return Err("the Root's answer had no tokens".into()) };
    save(config, machine, command, root, name)?;
    println!("enrolled as {name}; tokens saved in {}", config.state_dir.display());
    Ok(())
}

fn read_enrollment_token(file: Option<&str>) -> Result<String, String> {
    if let Some(path) = file {
        let text = std::fs::read_to_string(path).map_err(|_| "the token file cannot be read".to_string())?;
        let text = text.trim();
        return if text.is_empty() { Err("the token file is empty".into()) } else { Ok(text.to_string()) };
    }
    std::env::var("MS_ENROLLMENT_TOKEN").ok().filter(|t| !t.is_empty())
        .ok_or_else(|| "give the enrollment token with --enrollment-token-file or the MS_ENROLLMENT_TOKEN variable (never as a plain argument)".to_string())
}

fn save(config: &Config, machine: &str, command: &str, root: &str, name: &str) -> Result<(), String> {
    use std::os::unix::fs::DirBuilderExt;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&config.state_dir).map_err(|e| e.to_string())?;
    write_private(&config.token_file(), machine.as_bytes()).map_err(|e| e.to_string())?;
    write_private(&config.command_token_file(), command.as_bytes()).map_err(|e| e.to_string())?;
    write_private(&config.settings_file(), json!({"root": root, "name": name}).to_string().as_bytes()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn root_addresses() {
        assert_eq!(valid_root("http://192.168.100.40:9100/").unwrap(), "http://192.168.100.40:9100");
        for bad in ["ftp://x", "192.168.1.1", "http://", "http://user:pw@host", "http://host?x=1", "http://host#f", ""] {
            assert!(valid_root(bad).is_err(), "{bad}");
        }
    }
}
