//! The two constant installer scripts that run INSIDE a VM, as root, to put an app on top of it. They are fixed text: no request data is ever put in them.
//! The macOS helper has the same text in `agent/macos/Sources/AgentCore/Apps/AppInstallScripts.swift`.
//!
//! Each script is a short header (which app, which vendor URL, which packages, which environment) followed by the one shared body.
//! The body does the steps in order: stop early when the app is already there; install the prerequisites; download the vendor installer to a file with a time
//! limit; print its SHA-256; run the file with `bash` (never `curl | bash`); look for the command; read its version; print the result lines after a marker line.

/// The line before the result lines. The helper reads only what comes after the last one, so an installer that prints `installed=true` changes nothing.
pub const RESULT_MARKER: &str = "metaservice-app-result";

macro_rules! installer_script {
    ($header:literal) => {
        concat!($header, r##"
RESULT_MARKER='metaservice-app-result'
DOWNLOAD_SECONDS=120
VERSION_SECONDS=20
LOG_LINES=50
LOG_BYTES=20000
SEARCH_DIRS='/root/.local/bin /usr/local/bin /usr/bin /root/.npm-global/bin /root/.hermes/bin /root/.openclaw/bin /root/.cargo/bin'
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/root/.local/bin"
WORK=$(mktemp -d /tmp/metaservice-app.XXXXXX) || exit 1
LOG="$WORK/log"
FILE="$WORK/installer.sh"
VERSION=''
SHA256=''
: > "$LOG"

report() {
  tail -n "$LOG_LINES" "$LOG" | tail -c "$LOG_BYTES"
  rm -rf "$WORK"
  echo "$RESULT_MARKER"
  echo "app=$APP"
  echo "installed=$1"
  [ -z "$VERSION" ] || echo "version=$VERSION"
  [ -z "$SHA256" ] || echo "sha256=$SHA256"
  [ -z "$2" ] || echo "failure=$2"
  exit 0
}

find_app() {
  command -v "$APP" 2>/dev/null && return 0
  for dir in $SEARCH_DIRS "$(npm prefix -g 2>/dev/null)/bin"; do
    [ -x "$dir/$APP" ] && { echo "$dir/$APP"; return 0; }
  done
  return 1
}

read_version() {
  VERSION=$(timeout "$VERSION_SECONDS" "$1" --version </dev/null 2>/dev/null | head -n 1 | tr -d '\r')
}

BIN=$(find_app) && { read_version "$BIN"; report false; }
command -v apt-get >/dev/null 2>&1 || report false no_package_manager
DEBIAN_FRONTEND=noninteractive apt-get update -y </dev/null >>"$LOG" 2>&1 || report false prerequisites_failed
DEBIAN_FRONTEND=noninteractive apt-get install -y $PREREQUISITES </dev/null >>"$LOG" 2>&1 || report false prerequisites_failed
curl -fsSL --max-time "$DOWNLOAD_SECONDS" -o "$FILE" "$URL" </dev/null >>"$LOG" 2>&1 || report false download_failed
SHA256=$(sha256sum "$FILE" | cut -d ' ' -f 1)
run_installer "$FILE" </dev/null >>"$LOG" 2>&1 || report false install_failed
BIN=$(find_app) || report false install_failed
read_version "$BIN"
report true
"##)
    };
}

/// Installs OpenClaw. The environment is the one MAAS uses: no onboarding, no prompts, npm install, the pinned version, and the install URL variable.
pub const OPENCLAW_SCRIPT: &str = installer_script!(
    r##"APP=openclaw
URL='https://openclaw.ai/install.sh'
PREREQUISITES='curl ca-certificates'
run_installer() {
  env -i HOME=/root USER=root LOGNAME=root PATH="$PATH" CI=1 DEBIAN_FRONTEND=noninteractive OPENCLAW_NO_ONBOARD=1 OPENCLAW_NO_PROMPT=1 OPENCLAW_INSTALL_METHOD=npm OPENCLAW_VERSION=2026.9.4 "OPENCLAW_INSTALL_URL=$URL" bash "$1"
}"##
);

/// Installs Hermes. `git` and `libatomic1` are what its bundled node needs on a minimal base.
pub const HERMES_SCRIPT: &str = installer_script!(
    r##"APP=hermes
URL='https://hermes-agent.nousresearch.com/install.sh'
PREREQUISITES='curl ca-certificates git libatomic1'
run_installer() {
  env -i HOME=/root USER=root LOGNAME=root PATH="$PATH" CI=1 DEBIAN_FRONTEND=noninteractive bash "$1"
}"##
);
