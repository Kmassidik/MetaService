//! SSH keys per VM: the list of public keys that may log in as root of ONE workload, checked here and written inside it.
//! Where it lives: Linux helper, this file (rules, the fixed script, the report) and `ssh_keys_tests.rs` (route and engine tests).
//! The macOS helper has the same rules in `agent/macos/Sources/AgentCore/SshKeys/`.
//!
//! The keys travel on the standard input of `incus exec`, never in an argument, and the script is a constant: no shell text is ever built from key data.
use serde::Serialize;
use serde_json::Value;

pub const MAX_KEYS: usize = 20;
pub const MAX_LINE_BYTES: usize = 800;
const MAX_COMMENT_CHARS: usize = 64;
const MAX_BASE64_PADDING: usize = 3;
/// The only key types a line may start with. Nothing may come before the type, so no `command=` or other option can be smuggled in.
const KEY_TYPES: [&str; 6] = ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "ssh-rsa", "sk-ssh-ed25519@openssh.com"];
const FIELD_KEYS: &str = "keys";
const FIELD_INSTALL_SSHD: &str = "install_sshd";
/// What the report line starts with; the state word follows it.
pub const REPORT_PREFIX: &str = "sshd=";

/// Writes the new list next to the real file and moves it over, so a login never sees a half-written list. Reads the keys from standard input.
/// Then reports sshd: "running" when a process is called sshd, "installed" when the program exists, "missing" otherwise. It installs and starts nothing.
pub const SCRIPT: &str = "set -e
umask 077
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys.new
chmod 600 /root/.ssh/authorized_keys.new
mv -f /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys
if cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; then
  echo sshd=running
elif command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; then
  echo sshd=installed
else
  echo sshd=missing
fi
";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Sshd {
    Running,
    Installed,
    Missing,
}

/// The answer to `PUT /v1/workloads/{id}/ssh-keys`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Applied {
    pub applied: usize,
    pub sshd: Sshd,
    /// Present only when the call asked for the SSH server to be installed: true when this call installed the package.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub installed: Option<bool>,
}

/// The request body: the checked keys and whether the helper should also install and start the SSH server inside the VM (default false).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SshRequest {
    pub keys: KeyList,
    pub install_sshd: bool,
}

impl SshRequest {
    /// Reads the request body: an object with `keys` (a list of strings) and optionally `install_sshd` (true or false). Any other field is refused.
    pub fn parse(body: &[u8]) -> Result<SshRequest, String> {
        let Ok(Value::Object(object)) = serde_json::from_slice::<Value>(body) else { return Err("body must be a JSON object".into()) };
        if let Some(extra) = object.keys().find(|name| ![FIELD_KEYS, FIELD_INSTALL_SSHD].contains(&name.as_str())) {
            return Err(format!("unknown field {extra}"));
        }
        let install_sshd = match object.get(FIELD_INSTALL_SSHD) {
            None => false,
            Some(Value::Bool(flag)) => *flag,
            Some(_) => return Err("install_sshd must be true or false".into()),
        };
        let Some(Value::Array(items)) = object.get(FIELD_KEYS) else { return Err("keys must be a list".into()) };
        let lines: Option<Vec<String>> = items.iter().map(|item| item.as_str().map(str::to_string)).collect();
        Ok(SshRequest { keys: KeyList::from_lines(lines.ok_or("keys must be a list of strings")?)?, install_sshd })
    }
}

/// A list of keys that passed every rule. The only way to make one is `from_lines` (or `SshRequest::parse`), so whatever holds one holds a checked list.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyList(Vec<String>);

impl KeyList {
    /// Refuses the whole list when it is too long or any line is not one plain public key. The message names the position, never the key.
    pub fn from_lines(lines: Vec<String>) -> Result<KeyList, String> {
        if lines.len() > MAX_KEYS {
            return Err(format!("keys has too many items (at most {MAX_KEYS})"));
        }
        match lines.iter().position(|line| !is_valid_key(line)) {
            Some(index) => Err(format!("keys/{index} is not a valid single-line SSH public key")),
            None => Ok(KeyList(lines)),
        }
    }

    pub fn count(&self) -> usize {
        self.0.len()
    }

    /// What goes on standard input: every key on its own line, a newline after the last one, and nothing at all for an empty list.
    pub fn file_content(&self) -> Vec<u8> {
        self.0.iter().flat_map(|key| key.bytes().chain(std::iter::once(b'\n'))).collect()
    }
}

/// One line: a key type, one space, base64, and an optional one-word comment. Anything else (options, quotes, line breaks, NUL) is refused.
pub fn is_valid_key(line: &str) -> bool {
    if line.len() > MAX_LINE_BYTES {
        return false;
    }
    let mut parts = line.split(' ');
    let (Some(kind), Some(blob), comment, None) = (parts.next(), parts.next(), parts.next(), parts.next()) else { return false };
    KEY_TYPES.contains(&kind) && is_base64(blob) && comment.is_none_or(is_comment)
}

fn is_base64(text: &str) -> bool {
    let body = text.trim_end_matches('=');
    text.len() - body.len() <= MAX_BASE64_PADDING && !body.is_empty() && body.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/')
}

fn is_comment(text: &str) -> bool {
    (1..=MAX_COMMENT_CHARS).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_alphanumeric() || b"._@+:-".contains(&b))
}

/// The `incus` arguments for the one fixed call: no key is in them, and the script is the constant above.
pub fn incus_call(instance: &str) -> Vec<String> {
    ["exec", instance, "--", "/bin/sh", "-c", SCRIPT].iter().map(|part| part.to_string()).collect()
}

/// The state the script printed, or None when the output has no report line (the script did not finish).
pub fn parse_state(output: &str) -> Option<Sshd> {
    let word = output.lines().filter_map(|line| line.strip_prefix(REPORT_PREFIX)).next_back()?;
    match word {
        "running" => Some(Sshd::Running),
        "installed" => Some(Sshd::Installed),
        "missing" => Some(Sshd::Missing),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BLOB: &str = "AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE01";

    #[test]
    fn every_allowed_key_type_is_accepted_with_and_without_a_comment() {
        for kind in KEY_TYPES {
            assert!(is_valid_key(&format!("{kind} {BLOB} alice@laptop")), "{kind}");
            assert!(is_valid_key(&format!("{kind} {BLOB}")), "{kind} without a comment");
        }
        assert!(is_valid_key(&format!("ssh-rsa {BLOB}== a.b_c-d+e:f@g")), "padding and the full comment alphabet");
    }

    #[test]
    fn every_kind_of_bad_line_is_refused() {
        let long_comment = format!("ssh-ed25519 {BLOB} {}", "a".repeat(MAX_COMMENT_CHARS + 1));
        let bad = [
            format!("ssh-ed25519 {BLOB} a\nssh-ed25519 {BLOB} b"), format!("ssh-ed25519 {BLOB} a\r"), format!("ssh-ed25519 {BLOB} a\n"), format!("ssh-ed25519 {BLOB} a\0b"),
            format!("command=\"/bin/sh\" ssh-ed25519 {BLOB}"), format!("no-pty ssh-ed25519 {BLOB}"), format!("ssh-dss {BLOB}"), format!("ssh-ed25519{BLOB}"),
            format!("ssh-ed25519  {BLOB}"), format!("ssh-ed25519 {BLOB} \"quoted\""), format!("ssh-ed25519 {BLOB} a;b"), format!("ssh-ed25519 {BLOB} a b"),
            format!("ssh-ed25519 {BLOB} $(id)"), "ssh-ed25519 ".into(), "ssh-ed25519".into(), String::new(), format!(" ssh-ed25519 {BLOB}"), long_comment,
            format!("ssh-ed25519 {BLOB}===="), "ssh-ed25519 not*base64".into(), format!("ssh-ed25519 {BLOB} "), "ssh-ed25519 ====".into(),
        ];
        for line in bad {
            assert!(!is_valid_key(&line), "{line:?}");
        }
    }

    #[test]
    fn a_line_over_the_limit_is_refused() {
        let fits = format!("ssh-ed25519 {}", "A".repeat(MAX_LINE_BYTES - "ssh-ed25519 ".len()));
        assert_eq!(fits.len(), MAX_LINE_BYTES);
        assert!(is_valid_key(&fits));
        assert!(!is_valid_key(&format!("{fits}A")));
    }

    #[test]
    fn twenty_keys_are_fine_and_twenty_one_are_not() {
        let key = format!("ssh-ed25519 {BLOB}");
        assert!(KeyList::from_lines(vec![key.clone(); MAX_KEYS]).is_ok());
        assert!(KeyList::from_lines(vec![key; MAX_KEYS + 1]).is_err());
        assert_eq!(KeyList::from_lines(Vec::new()).unwrap().count(), 0);
    }

    #[test]
    fn the_refusal_names_the_position_and_never_the_key() {
        let message = KeyList::from_lines(vec![format!("ssh-ed25519 {BLOB}"), format!("ssh-ed25519 {BLOB} \"oops\"")]).unwrap_err();
        assert!(message.contains("keys/1"), "{message}");
        assert!(!message.contains(BLOB), "{message}");
    }

    #[test]
    fn the_body_is_read_strictly() {
        let key = format!("ssh-ed25519 {BLOB} a");
        let body = |text: String| SshRequest::parse(text.as_bytes()).map(|request| request.keys);
        assert_eq!(body(format!(r#"{{"keys":["{key}"]}}"#)).unwrap().count(), 1);
        assert_eq!(body(r#"{"keys":[]}"#.into()).unwrap().count(), 0);
        for bad in [r#"{}"#.to_string(), r#"{"keys":"x"}"#.into(), r#"{"keys":[5]}"#.into(), r#"{"keys":[],"extra":1}"#.into(), "not json".into(), "[]".into(),
                    format!(r#"{{"keys":["{key}\nssh-rsa AAAA"]}}"#)] {
            assert!(body(bad.clone()).is_err(), "{bad}");
        }
    }

    #[test]
    fn the_file_content_has_one_key_per_line_and_a_closing_newline() {
        let list = KeyList::from_lines(vec![format!("ssh-ed25519 {BLOB}"), format!("ssh-rsa {BLOB} b")]).unwrap();
        assert_eq!(String::from_utf8(list.file_content()).unwrap(), format!("ssh-ed25519 {BLOB}\nssh-rsa {BLOB} b\n"));
        assert!(KeyList::from_lines(Vec::new()).unwrap().file_content().is_empty(), "an empty list leaves an empty managed file");
    }

    #[test]
    fn the_call_is_a_fixed_exec_of_the_fixed_script_with_no_key_in_it() {
        assert_eq!(incus_call("ms-w-1"), ["exec", "ms-w-1", "--", "/bin/sh", "-c", SCRIPT]);
        assert_eq!(incus_call("ms-w-2").last(), incus_call("ms-w-1").last());
    }

    #[test]
    fn the_script_writes_atomically_with_the_right_modes_and_installs_nothing() {
        for line in ["mkdir -p /root/.ssh", "chmod 700 /root/.ssh", "cat > /root/.ssh/authorized_keys.new", "chmod 600 /root/.ssh/authorized_keys.new", "mv -f /root/.ssh/authorized_keys.new /root/.ssh/authorized_keys"] {
            assert!(SCRIPT.contains(line), "{line}");
        }
        let at = |needle: &str| SCRIPT.find(needle).unwrap();
        assert!(at("cat > ") < at("chmod 600") && at("chmod 600") < at("mv -f"), "write, then set the mode, then swap in");
        assert!(!SCRIPT.contains("apt-get") && !SCRIPT.contains("systemctl"));
        assert!(SCRIPT.contains(REPORT_PREFIX));
    }

    #[test]
    fn the_script_is_valid_shell_text() {
        let status = std::process::Command::new("/bin/sh").args(["-n", "-c", SCRIPT]).status().unwrap();
        assert!(status.success());
    }

    #[test]
    fn the_report_line_is_read_and_nothing_else_is_guessed() {
        assert_eq!(parse_state("sshd=running\n"), Some(Sshd::Running));
        assert_eq!(parse_state("noise\nsshd=installed\n"), Some(Sshd::Installed));
        assert_eq!(parse_state("sshd=missing"), Some(Sshd::Missing));
        assert_eq!(parse_state(""), None);
        assert_eq!(parse_state("sshd=maybe\n"), None);
    }
}
