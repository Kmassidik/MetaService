#!/bin/sh
# Installs the join-share hub on the Mac Mini, from this checkout (the branch's own clone, never the running ~/MetaService):
#   1. builds the two binaries (cargo build --release);
#   2. puts the root helper where only root can change it and allows exactly that one program in sudoers (checked with visudo before it is installed);
#   3. writes state/hub.env (mode 600) from the JOIN_SHARE_* settings given on the command line, if it does not exist yet;
#   4. installs and starts the boot job io.metaservice.joinshare (a LaunchDaemon that runs as the normal user).
# Settings that have no safe default must be given the first time:  JOIN_SHARE_ENDPOINT=<public-ip>:<udp-port>  JOIN_SHARE_PUBLIC_URL=https://<hostname>
# Run it again after a `git pull`: it rebuilds and restarts the hub only. `sh install-hub.sh remove` takes everything it made away again.
# MAAS, the parent and the existing LaunchDaemons are not touched.
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
STATE="$HERE/state"
CARGO="$HOME/.cargo/bin/cargo"
ROOT_BIN_DIR=/usr/local/libexec/join-share
ROOT_BIN="$ROOT_BIN_DIR/join-share-root"
SUDOERS=/etc/sudoers.d/join-share
LABEL=io.metaservice.joinshare
PLIST="/Library/LaunchDaemons/$LABEL.plist"
USER_NAME=$(id -un)
GROUP_NAME=$(id -gn)
PARENT_DB_DEFAULT="$HOME/MetaService/control-plane/arm64/state/root.sqlite3"
BUILDS_DEFAULT="$HOME/MetaService/control-plane/arm64/state/agent-builds"
MAC_AGENT_DEFAULT="$HOME/MetaService/agent/macos/.build/debug/metaservice-agent"

say() { printf '%s\n' "$*"; }

if [ "${1:-}" = remove ]; then
  sudo -n launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
  sudo -n rm -f "$PLIST" "$SUDOERS"
  if [ -x "$ROOT_BIN" ]; then sudo -n "$ROOT_BIN" pf-unload >/dev/null 2>&1 || true; sudo -n "$ROOT_BIN" down >/dev/null 2>&1 || true; fi
  sudo -n rm -rf "$ROOT_BIN_DIR"
  say "removed the boot job, the sudoers entry and the root helper; the state folder $STATE is kept"
  exit 0
fi

say "== build"
(cd "$HERE/hub" && "$CARGO" build --release)
BIN="$HERE/hub/target/release"
[ -x "$BIN/join-share" ] && [ -x "$BIN/join-share-root" ] || { say "build did not make both programs"; exit 1; }

say "== root helper and sudoers"
sudo -n mkdir -p "$ROOT_BIN_DIR"
sudo -n cp "$BIN/join-share-root" "$ROOT_BIN"
sudo -n chown -R root:wheel "$ROOT_BIN_DIR"
sudo -n chmod 755 "$ROOT_BIN_DIR" "$ROOT_BIN"
TMP=$(mktemp)
printf '%s ALL=(root) NOPASSWD: %s *\n' "$USER_NAME" "$ROOT_BIN" > "$TMP"
sudo -n visudo -cf "$TMP" >/dev/null
sudo -n install -m 440 -o root -g wheel "$TMP" "$SUDOERS"
rm -f "$TMP"

say "== settings"
mkdir -p "$STATE" && chmod 700 "$STATE"
if [ ! -f "$STATE/hub.env" ]; then
  : "${JOIN_SHARE_ENDPOINT:?give JOIN_SHARE_ENDPOINT=<public-ip>:<udp-port> the first time}"
  : "${JOIN_SHARE_PUBLIC_URL:?give JOIN_SHARE_PUBLIC_URL=https://<hostname> the first time}"
  umask 077
  cat > "$STATE/hub.env" <<EOF
JOIN_SHARE_ENDPOINT=$JOIN_SHARE_ENDPOINT
JOIN_SHARE_PUBLIC_URL=$JOIN_SHARE_PUBLIC_URL
JOIN_SHARE_STATE=$STATE
JOIN_SHARE_ROOT_HELPER=$ROOT_BIN
JOIN_SHARE_PARENT_DB=${JOIN_SHARE_PARENT_DB:-$PARENT_DB_DEFAULT}
JOIN_SHARE_BUILDS_DIR=${JOIN_SHARE_BUILDS_DIR:-$BUILDS_DEFAULT}
JOIN_SHARE_MAC_AGENT=${JOIN_SHARE_MAC_AGENT:-$MAC_AGENT_DEFAULT}
EOF
  say "wrote $STATE/hub.env"
else
  say "kept $STATE/hub.env"
fi

say "== boot job"
TMP=$(mktemp)
cat > "$TMP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>UserName</key><string>$USER_NAME</string>
	<key>GroupName</key><string>$GROUP_NAME</string>
	<key>WorkingDirectory</key><string>$HERE</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/sh</string>
		<string>-c</string>
		<string>set -a; . "$STATE/hub.env"; exec "$BIN/join-share" serve</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
		<key>HOME</key><string>$HOME</string>
	</dict>
	<key>RunAtLoad</key><true/>
	<key>KeepAlive</key><true/>
	<key>ThrottleInterval</key><integer>10</integer>
	<key>StandardOutPath</key><string>$STATE/hub.log</string>
	<key>StandardErrorPath</key><string>$STATE/hub.log</string>
</dict>
</plist>
EOF
sudo -n launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
sudo -n install -m 644 -o root -g wheel "$TMP" "$PLIST"
rm -f "$TMP"
# bootout returns before launchd has freed the label, and a bootstrap in that moment fails with an I/O error: wait, then retry a few times.
tries=0
until sudo -n launchctl bootstrap system "$PLIST" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt 10 ] || { say "launchd would not load $LABEL after $tries tries"; exit 1; }
  sleep 2
done
say "started $LABEL; log: $STATE/hub.log"
