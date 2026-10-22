//! Installing and locking the SSH server inside a VM, on top of the keys in `ssh_keys.rs` (request flag `install_sshd`).
//! Where it lives: Linux helper, this file (the fixed script, its report, the plain-words failures) and `ssh_install_tests.rs`.
//! The macOS helper has the same script text in `agent/macos/Sources/AgentCore/SshKeys/SshdInstallScript.swift`.
//!
//! It runs AFTER the keys are written (a stuck or failed install never loses keys), as its own `incus exec` with no standard input and no request data.
use crate::engine::Engine;
use crate::models::EngineError;
use crate::service::Failure;
use crate::ssh_keys::{self, Applied, SshRequest, Sshd};

/// The error code of the 502 answer when the SSH server could not be made to listen.
pub const ERROR_CODE: &str = "sshd_install_failed";
const INSTALLED_PREFIX: &str = "installed=";
const FAILURE_PREFIX: &str = "failure=";

/// Everything here is fixed text. It installs the server when it is missing (apt-get, apk, dnf, yum in that order), makes it key-only, starts it, and prints
/// `sshd=<state>`, `installed=true|false` and, when something went wrong, `failure=<code>`. Package manager noise is thrown away inside the VM.
pub const INSTALL_SCRIPT: &str = r##"PATH="$PATH:/usr/sbin:/sbin:/usr/local/sbin"
umask 022
MAIN=/etc/ssh/sshd_config
DROPIN_DIR=/etc/ssh/sshd_config.d
DROPIN=/etc/ssh/sshd_config.d/10-metaservice.conf
BEGIN_MARK='# BEGIN metaservice'
END_MARK='# END metaservice'
WORK=/tmp/metaservice-ssh.$$
NO_MANAGER=2
WAIT_TRIES=10
installed=false
changed=false
mkdir -p "$WORK"

settings() {
cat <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
EOF
}

has_sshd() { command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ]; }
is_running() { cat /proc/[0-9]*/comm 2>/dev/null | grep -qx sshd; }
is_listening() { cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -Eq '^ *[0-9]+: [0-9A-Fa-f]+:0016 [0-9A-Fa-f]+:[0-9A-Fa-f]+ 0A '; }
is_up() { is_listening; }

report() {
  if is_up; then state=running
  elif has_sshd; then state=installed
  else state=missing
  fi
  rm -rf "$WORK"
  echo "sshd=$state"
  echo "installed=$installed"
  [ -z "$1" ] || echo "failure=$1"
  exit 0
}

install_package() {
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update </dev/null >/dev/null 2>&1 &&
      DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server </dev/null >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache openssh </dev/null >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install openssh-server </dev/null >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum -y install openssh-server </dev/null >/dev/null 2>&1
  else
    return "$NO_MANAGER"
  fi
}

ensure_package() {
  install_package
  status=$?
  [ "$status" -ne "$NO_MANAGER" ] || report no_package_manager
  [ "$status" -eq 0 ] || report install_failed
  installed=true
  has_sshd || report install_failed
}

same_file() { [ -f "$2" ] && [ "$(cat "$1")" = "$(cat "$2")" ]; }

write_dropin() {
  mkdir -p "$DROPIN_DIR"
  settings > "$DROPIN.new"
  same_file "$DROPIN.new" "$DROPIN" && { rm -f "$DROPIN.new"; return 0; }
  if [ -f "$DROPIN" ]; then cp -p "$DROPIN" "$WORK/dropin.old"; else : > "$WORK/dropin.created"; fi
  mv -f "$DROPIN.new" "$DROPIN"
  changed=true
}

write_main_block() {
  { echo "$BEGIN_MARK"; settings; echo "$END_MARK"; sed "/$BEGIN_MARK/,/$END_MARK/d" "$MAIN"; } > "$MAIN.new"
  same_file "$MAIN.new" "$MAIN" && { rm -f "$MAIN.new"; return 0; }
  cp -p "$MAIN" "$WORK/main.old"
  mv -f "$MAIN.new" "$MAIN"
  changed=true
}

has_include() { grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config[.]d/[*][.]conf' "$MAIN" 2>/dev/null; }

restore_config() {
  [ ! -f "$WORK/dropin.old" ] || cp -p "$WORK/dropin.old" "$DROPIN"
  [ ! -f "$WORK/dropin.created" ] || rm -f "$DROPIN"
  [ ! -f "$WORK/main.old" ] || cp -p "$WORK/main.old" "$MAIN"
}

apply_config() {
  write_dropin
  has_include || write_main_block
  sshd -t </dev/null >/dev/null 2>&1 && return 0
  restore_config
  report config_invalid
}

systemd_unit() {
  for candidate in ssh sshd; do
    systemctl cat "$candidate.service" </dev/null >/dev/null 2>&1 && { echo "$candidate"; return 0; }
  done
  return 1
}

reload_plain() {
  [ "$changed" = false ] && return 0
  [ -r /run/sshd.pid ] && kill -HUP "$(cat /run/sshd.pid)" 2>/dev/null
  return 0
}

start_plain() {
  is_running && { reload_plain; return 0; }
  mkdir -p /run/sshd
  sshd </dev/null >/dev/null 2>&1
}

start_systemd() {
  unit=$(systemd_unit) || return 1
  systemctl enable --now "$unit" </dev/null >/dev/null 2>&1 || return 1
  [ "$changed" = false ] && return 0
  systemctl reload "$unit" </dev/null >/dev/null 2>&1 || systemctl restart "$unit" </dev/null >/dev/null 2>&1
}

start_server() {
  [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1 && start_systemd && return 0
  start_plain
}

wait_until_up() {
  tries=0
  while [ "$tries" -lt "$WAIT_TRIES" ] && ! is_up; do
    sleep 1
    tries=$((tries + 1))
  done
}

has_sshd || ensure_package
ssh-keygen -A </dev/null >/dev/null 2>&1
mkdir -p /run/sshd
apply_config
start_server
wait_until_up
is_up || report not_listening
report
"##;

/// Why the SSH server could not be made to listen. The code is what the script prints; the message is what the person reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SshdFailure {
    NoPackageManager,
    InstallFailed,
    ConfigInvalid,
    NotListening,
}

impl SshdFailure {
    pub fn from_code(code: &str) -> Option<SshdFailure> {
        match code {
            "no_package_manager" => Some(SshdFailure::NoPackageManager),
            "install_failed" => Some(SshdFailure::InstallFailed),
            "config_invalid" => Some(SshdFailure::ConfigInvalid),
            "not_listening" => Some(SshdFailure::NotListening),
            _ => None,
        }
    }

    pub fn message(self) -> &'static str {
        match self {
            SshdFailure::NoPackageManager => "The VM has no package manager the helper knows (apt, apk, dnf, yum), so it cannot install the SSH server.",
            SshdFailure::InstallFailed => "The VM could not download the SSH server. Check that the VM has internet access.",
            SshdFailure::ConfigInvalid => "The SSH server did not accept its settings, so nothing was changed.",
            SshdFailure::NotListening => "The SSH server was installed but is not listening on port 22.",
        }
    }
}

/// What the install script printed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct InstallReport {
    pub sshd: Sshd,
    pub installed: bool,
    pub failure: Option<SshdFailure>,
}

/// The `incus` arguments for the install call: a fixed exec of the constant above, nothing from the request in them.
pub fn incus_call(instance: &str) -> Vec<String> {
    ["exec", instance, "--", "/bin/sh", "-c", INSTALL_SCRIPT].iter().map(|part| part.to_string()).collect()
}

/// Reads the script's lines. None when there is no `sshd=` line (the script did not finish) or a failure code is not one we know.
pub fn parse_report(output: &str) -> Option<InstallReport> {
    let value = |prefix: &str| output.lines().filter_map(|line| line.strip_prefix(prefix)).next_back();
    let sshd = ssh_keys::parse_state(output)?;
    let installed = value(INSTALLED_PREFIX) == Some("true");
    let failure = match value(FAILURE_PREFIX) {
        None => None,
        Some(code) => Some(SshdFailure::from_code(code)?),
    };
    Some(InstallReport { sshd, installed, failure })
}

/// Writes the keys first, then (when asked) installs and starts the SSH server. A failure of the install step is `Failure::Sshd`; the keys stay written.
pub fn apply(engine: &dyn Engine, id: &str, request: &SshRequest) -> Result<Applied, Failure> {
    let sshd = engine.apply_ssh_keys(id, &request.keys)?;
    let applied = request.keys.count();
    if !request.install_sshd {
        return Ok(Applied { applied, sshd, installed: None });
    }
    let report = match engine.install_sshd(id) {
        Ok(report) => report,
        Err(EngineError::NotFound) => return Err(Failure::NotFound),
        Err(EngineError::Failed(_)) => return Err(Failure::Sshd(SshdFailure::InstallFailed)),
    };
    match report.failure {
        Some(failure) => Err(Failure::Sshd(failure)),
        None => Ok(Applied { applied, sshd: report.sshd, installed: Some(report.installed) }),
    }
}
