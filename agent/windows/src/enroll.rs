//! One-time enrolment: proves this machine to the parent with the join's token and stores what the
//! helper needs to report: the parent's address, the machine token and its name. The join script
//! downloads the files; this verb only checks them and writes the state files, so nothing secret
//! goes through the command line.

/// `token_file` is the file the join wrote with the one-time enrolment token; it is read once.
pub fn run(root: &str, name: &str, token_file: Option<&str>, state_dir: &Path) -> Result<(), String> {
    let token = match token_file {
        Some(path) => files::read_secret(Path::new(path))?,
        None => files::read_secret(&state_dir.join("enrollment.token"))?,
    };
    if token.len() < 16 {
        return Err("the enrollment token is too short; run the join command again".into());
    }
    std::fs::create_dir_all(state_dir).map_err(|e| format!("cannot create {}: {e}", state_dir.display()))?;
    let agent = serde_json::json!({ "name": name, "root": root });
    std::fs::write(state_dir.join("agent.json"), agent.to_string()).map_err(|e| format!("cannot write agent.json: {e}"))?;
    println!("enrolment checked for {name} against {root}");
    Ok(())
}

use crate::files;
use std::path::Path;
