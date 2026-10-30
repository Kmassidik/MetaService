#!/bin/sh
# Runs the join script against a stub hub with every external command replaced by a stub in a temporary PATH. No root, no WireGuard.
# Run: sh join-share/script/tests/run.sh      (TEST_SH=dash sh run.sh runs the script under dash)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../join.sh"
SYSTEM_PATH=/usr/bin:/bin:/usr/sbin:/sbin
PASSED=0
FAILED=0

ok() { # name, then a command whose success means pass
  name=$1; shift
  if "$@" >/dev/null 2>&1; then PASSED=$((PASSED + 1)); echo "PASS  $name"; else FAILED=$((FAILED + 1)); echo "FAIL  $name"; fi
}
has() { grep -q -- "$2" "$1"; }
lacks() { ! grep -q -- "$2" "$1" 2>/dev/null; }
count_is() { [ "$(grep -c -- "$2" "$1" 2>/dev/null)" = "$3" ]; }

# ---- the stubs ---------------------------------------------------------------------------------

stub() { # name, body
  printf '#!/bin/sh\n%s\n' "$2" > "$BIN/$1"
  chmod +x "$BIN/$1"
}

make_wg_tools() {
  stub wg 'echo "wg $*" >> "$CALLS"
case "$1" in
  genkey) echo "PRIVATEKEYPRIVATEKEYPRIVATEKEYPRIVATEKE=" ;;
  pubkey) cat >/dev/null; echo "PUBLICKEYPUBLICKEYPUBLICKEYPUBLICKEYPUBL=" ;;
esac'
  stub wg-quick 'echo "wg-quick $*" >> "$CALLS"'
  [ "$OS_NAME" != Darwin ] || stub wireguard-go 'exit 0'
}

new_world() { # os cpu, optional: wg-present
  OS_NAME=$1
  T=$(mktemp -d)
  BIN="$T/bin"; mkdir -p "$BIN" "$T/home" "$T/hub"
  CALLS="$T/calls.log"; : > "$CALLS"
  AGENT_LOG="$T/agent.log"
  stub uname "case \"\$1\" in -s) echo $1 ;; -m) echo $2 ;; esac"
  stub sudo 'echo "sudo $*" >> "$CALLS"
case "$1" in -v|-n) exit 0 ;; esac
exec "$@"'
  stub curl 'echo "curl $*" >> "$CALLS"; exec /usr/bin/curl "$@"'
  stub sha256sum 'exec shasum -a 256 "$@"'
  stub systemctl 'echo "systemctl $*" >> "$CALLS"
[ "$1 $2" = "--user show-environment" ] && [ -f "$NO_BUS" ] && exit 1
exit 0'
  stub id 'if [ "$1" = -u ] && [ -f "$AS_ROOT" ]; then echo 0; else exec /usr/bin/id "$@"; fi'
  stub launchctl 'echo "launchctl $*" >> "$CALLS"'
  stub modinfo 'exit 0'
  stub loginctl 'echo "loginctl $*" >> "$CALLS"
case "$1" in show-user) [ -f "$LINGER" ] && echo Linger=yes || echo Linger=no ;; enable-linger) : > "$LINGER" ;; esac'
  stub brew 'echo "brew $*" >> "$CALLS"; cp "$STUBS/.wg" "$STUBS/wg"; cp "$STUBS/.wg-quick" "$STUBS/wg-quick"; cp "$STUBS/.wireguard-go" "$STUBS/wireguard-go"'
  stub dnf 'echo "dnf $*" >> "$CALLS"; cp "$STUBS/.wg" "$STUBS/wg"; cp "$STUBS/.wg-quick" "$STUBS/wg-quick"'
  [ "$OS_NAME" = Darwin ] && rm -f "$BIN/dnf" || rm -f "$BIN/brew"
  make_wg_tools
  for tool in wg wg-quick wireguard-go; do [ -f "$BIN/$tool" ] && mv "$BIN/$tool" "$BIN/.$tool"; done
  LINGER="$T/linger"; NO_BUS="$T/no-bus"; AS_ROOT="$T/as-root"
  mkdir -p "$T/systemd"; WG_DIR="$T/etc-wireguard"; DAEMONS="$T/daemons"; mkdir -p "$DAEMONS"
}

install_tools_already() { for tool in wg wg-quick wireguard-go; do [ -f "$BIN/.$tool" ] && cp "$BIN/.$tool" "$BIN/$tool"; done; : > "$LINGER"; }

start_hub() {
  bun "$HERE/stub-hub.ts" "$SCRIPT" "$T/hub" > "$T/hub/port" &
  HUB_PID=$!
  tries=0
  while [ ! -s "$T/hub/port" ] && [ "$tries" -lt 100 ]; do sleep 0.1; tries=$((tries + 1)); done
  HUB="http://127.0.0.1:$(head -n 1 "$T/hub/port")"
}

# join <link> <os> <cpu> <answer>  : the way a person runs it. Output in $T/out, exit code in $CODE.
join() {
  printf '%s\n' "$4" > "$T/tty"
  HOME="$T/home" PATH="$BIN:$SYSTEM_PATH" CALLS="$CALLS" LINGER="$LINGER" NO_BUS="$NO_BUS" AS_ROOT="$AS_ROOT" AGENT_LOG="$AGENT_LOG" STUBS="$BIN" \
  JOIN_TTY="${TTY_FILE:-$T/tty}" JOIN_SYSTEMD_DIR="$T/systemd" JOIN_WG_DIR="$WG_DIR" JOIN_DAEMON_DIR="$DAEMONS" JOIN_POLL_SECONDS=0 JOIN_POLL_MAX=5 \
  JOIN_SHARE_CORES=2 JOIN_SHARE_RAM_MB=4096 JOIN_SHARE_DISK_GB=20 \
  sh -c "curl -fsSL '$HUB/j/$1?os=$2&cpu=$3' | ${TEST_SH:-sh}" > "$T/out" 2>&1
  CODE=$?
  [ -z "${SHOW:-}" ] || { echo "---- exit $CODE"; tail -n 12 "$T/out"; }
}

finish_world() { [ -z "${DUMP:-}" ] || { echo "---- calls"; cat "$CALLS"; echo "---- out"; head -n 14 "$T/out"; }; [ -z "${KEEP:-}" ] || { echo "kept $T"; return 0; }; kill "$HUB_PID" 2>/dev/null; wait "$HUB_PID" 2>/dev/null; rm -rf "$T"; }

JOIN="\$T/home/.metaservice-join"
snapshot() { (cd "$T" && find home etc-wireguard daemons -type f 2>/dev/null | sort; grep -c '^sudo\|^brew\|^wg\|^systemctl\|^launchctl' "$CALLS") ; }

# ---- the scenarios -----------------------------------------------------------------------------

echo "== syntax"
ok "sh -n join.sh" sh -n "$SCRIPT"
if command -v dash >/dev/null 2>&1; then ok "dash -n join.sh" dash -n "$SCRIPT"; fi
ok "the four placeholders appear once each" sh -c "[ \$(grep -o '@LINK@\|@PUBLIC_URL@\|@OS@\|@CPU@' '$SCRIPT' | wc -l) -eq 4 ]"

echo "== mac arm64: happy path (WireGuard missing, brew installs it)"
new_world Darwin arm64; start_hub
join approve-mac mac arm64 y
J="$T/home/.metaservice-join"
ok "exit 0" [ "$CODE" = 0 ]
ok "check list says missing" has "$T/out" '\[missing\] *wg'
ok "the plan with the root commands was printed first" has "$T/out" 'wg-quick up'
ok "brew installed once, as the user (not through sudo)" sh -c "[ \$(grep -c '^brew install' '$CALLS') = 1 ] && ! grep -q 'sudo.*brew install' '$CALLS'"
ok "one sudo block ran the interface" count_is "$CALLS" '^sudo sh -c' 1
ok "wg config written, mode 600, private key inside" sh -c "[ \"\$(stat -f %Lp '$WG_DIR/metaservice.conf' 2>/dev/null || stat -c %a '$WG_DIR/metaservice.conf')\" = 600 ] && grep -q 'Address = 10.77.0.2/32' '$WG_DIR/metaservice.conf' && grep -q 'AllowedIPs = 10.77.0.1/32' '$WG_DIR/metaservice.conf'"
ok "wg-quick up with that config" has "$CALLS" "wg-quick up $WG_DIR/metaservice.conf"
ok "boot entry for WireGuard installed" test -f "$DAEMONS/io.metaservice.join.wg.plist"
ok "the code is shown" has "$T/out" 'Tell the admin'
ok "the registered body has the public key and no private key" sh -c "grep -q PUBLICKEYPUBLICKEY '$T/hub/register.json' && ! grep -q PRIVATEKEY '$T/hub/register.json' && grep -q '\"os\":\"mac\"' '$T/hub/register.json'"
ok "enroll ran with the parent address and name" has "$AGENT_LOG" 'enroll --root http://10.77.0.1:9102 --name far-pc'
ok "the enrollment token file is gone" test ! -e "$J/state/enroll.token"
ok "the token and the private key are never printed" sh -c "! grep -q 'tok-aaaa\|PRIVATEKEYPRIVATE' '$T/out' '$CALLS'"
ok "LaunchAgent bound to the WireGuard address" has "$T/home/Library/LaunchAgents/io.metaservice.join.plist" '<string>10.77.0.2</string>'
ok "LaunchAgent loaded" has "$CALLS" '^launchctl bootstrap'
ok "leave.sh and joined.env installed" sh -c "test -x '$J/leave.sh' && test -f '$J/joined.env' && sh -n '$J/leave.sh'"
ok "private key file is mode 600" sh -c "[ \"\$(stat -f %Lp '$J/wg.key' 2>/dev/null || stat -c %a '$J/wg.key')\" = 600 ]"

echo "== re-run on the joined machine changes nothing"
snapshot > "$T/before"
join approve-again mac arm64 y
snapshot > "$T/after"
ok "exit 0 and it says already joined" sh -c "[ $CODE = 0 ] && grep -q 'already joined' '$T/out'"
ok "no file and no command changed" cmp "$T/before" "$T/after"
ok "the new link was not used" count_is "$T/hub/hub.log" 'register' 1

echo "== leave.sh removes what was made"
HOME="$T/home" PATH="$BIN:$SYSTEM_PATH" CALLS="$CALLS" sh "$J/leave.sh" > "$T/leave.out" 2>&1
ok "leave exit 0" has "$T/leave.out" 'has left'
ok "folder, config, boot entry and LaunchAgent are gone" sh -c "test ! -e '$J' && test ! -e '$WG_DIR/metaservice.conf' && test ! -e '$DAEMONS/io.metaservice.join.wg.plist' && test ! -e '$T/home/Library/LaunchAgents/io.metaservice.join.plist'"
ok "interface taken down and agent unloaded" sh -c "grep -q 'wg-quick down' '$CALLS' && grep -q 'launchctl bootout' '$CALLS'"
finish_world

echo "== fedora x86_64: everything present, one sudo block"
new_world Linux x86_64; install_tools_already; start_hub
join approve-fedora linux x86_64 y
J="$T/home/.metaservice-join"
ok "exit 0" [ "$CODE" = 0 ]
ok "check list says found" has "$T/out" '\[found\] *wg'
ok "no package manager call" lacks "$CALLS" '^dnf'
ok "one sudo block" count_is "$CALLS" '^sudo sh -c' 1
ok "wg-quick service enabled and restarted" sh -c "grep -q 'systemctl enable wg-quick@metaservice' '$CALLS' && grep -q 'systemctl restart wg-quick@metaservice' '$CALLS'"
ok "user service written, bound to the WireGuard address, enabled" sh -c "grep -q -- '--bind 10.77.0.2 --heartbeat' '$T/home/.config/systemd/user/io.metaservice.join.service' && grep -q 'systemctl --user enable io.metaservice.join.service' '$CALLS'"
ok "enroll then the share limits reach run" has "$T/home/.config/systemd/user/io.metaservice.join.service" '--ram-allowance-mb 4096 --disk-allowance-gb 20'
ok "helper ran enroll, token file was mode 600" sh -c "grep -q 'enroll --root http://10.77.0.1:9102' '$AGENT_LOG' && grep -q 'tokenmode 600' '$AGENT_LOG'"
echo "== leave on Linux"
HOME="$T/home" PATH="$BIN:$SYSTEM_PATH" CALLS="$CALLS" sh "$J/leave.sh" > "$T/leave.out" 2>&1
ok "folder, config and user service are gone" sh -c "test ! -e '$J' && test ! -e '$WG_DIR/metaservice.conf' && test ! -e '$T/home/.config/systemd/user/io.metaservice.join.service'"
ok "services disabled" sh -c "grep -q 'systemctl disable --now wg-quick@metaservice' '$CALLS' && grep -q 'systemctl --user disable --now io.metaservice.join.service' '$CALLS'"
finish_world

echo "== fedora: missing packages are installed once, in the first sudo block"
new_world Linux x86_64; start_hub
join approve-pkgs linux x86_64 y
ok "exit 0" [ "$CODE" = 0 ]
ok "wg and wg-quick reported missing" sh -c "grep -q '\[missing\] *wg$' '$T/out' && grep -q '\[missing\] *wg-quick' '$T/out'"
ok "dnf install ran exactly once" count_is "$CALLS" '^dnf install -y wireguard-tools' 1
ok "linger enabled in the same block" count_is "$CALLS" '^loginctl enable-linger mac' 1
ok "two root runs: packages, then the interface; one password (sudo -v once)" sh -c "[ \$(grep -c '^sudo sh -c' '$CALLS') = 2 ] && [ \$(grep -c '^sudo -v' '$CALLS') = 1 ]"
ok "the dnf line was inside the first sudo block" sh -c "grep -n 'sudo sh -c\|^dnf' '$CALLS' | head -2 | tail -1 | grep -q dnf"
finish_world

echo "== user answers n: nothing changes"
new_world Linux x86_64; start_hub
join approve-no linux x86_64 n
ok "exit 0, says nothing was changed" sh -c "[ $CODE = 0 ] && grep -q 'Nothing was changed' '$T/out'"
ok "no state folder, no sudo, no install, no register" sh -c "test ! -e '$T/home/.metaservice-join' && ! grep -q '^sudo\|^dnf' '$CALLS' && ! grep -q register '$T/hub/hub.log'"
finish_world

echo "== os or cpu does not match"
new_world Linux x86_64; start_hub
join approve-mismatch mac arm64 y
ok "stops with a plain message" sh -c "[ $CODE != 0 ] && grep -q 'this computer is linux' '$T/out'"
ok "nothing ran" sh -c "! grep -q '^sudo\|^dnf' '$CALLS' && test ! -e '$T/home/.metaservice-join'"
join approve-cpu linux arm64 y
ok "cpu mismatch stops too" sh -c "[ $CODE != 0 ] && grep -q 'this computer is x86_64' '$T/out'"
finish_world

echo "== refused"
new_world Linux x86_64; install_tools_already; start_hub
join refuse-1 linux x86_64 y
ok "stops with the refused message" sh -c "[ $CODE != 0 ] && grep -q 'refused' '$T/out'"
ok "no config, no helper run, no joined marker" sh -c "test ! -e '$WG_DIR/metaservice.conf' && test ! -e '$AGENT_LOG' && test ! -e '$T/home/.metaservice-join/joined.env'"
finish_world

echo "== expired"
new_world Linux x86_64; install_tools_already; start_hub
join expire-1 linux x86_64 y
ok "stops with the expired message" sh -c "[ $CODE != 0 ] && grep -q 'expired' '$T/out'"
ok "no config and no helper run" sh -c "test ! -e '$WG_DIR/metaservice.conf' && test ! -e '$AGENT_LOG'"
finish_world

echo "== wrong sha256 stops before anything runs"
new_world Linux x86_64; install_tools_already; start_hub
join badsha-1 linux x86_64 y
ok "stops on the checksum" sh -c "[ $CODE != 0 ] && grep -q 'checksum does not match' '$T/out'"
ok "helper deleted, never run, no interface, no service" sh -c "test ! -e '$T/home/.metaservice-join/bin/metaservice-agent' && test ! -e '$AGENT_LOG' && test ! -e '$WG_DIR/metaservice.conf' && ! grep -q 'wg-quick\|--user enable' '$CALLS'"
ok "the enrollment token is deleted" test ! -e "$T/home/.metaservice-join/state/enroll.token"
finish_world

echo "== root, no systemd, no terminal, JOIN_SHARE_YES=1 (a container)"
new_world Linux arm64; install_tools_already; : > "$NO_BUS"; : > "$AS_ROOT"; rmdir "$T/systemd"; start_hub
JOIN_SHARE_YES=1; TTY_FILE=/nonexistent; export JOIN_SHARE_YES; join approve-box linux arm64 ""; unset JOIN_SHARE_YES TTY_FILE
J="$T/home/.metaservice-join"
ok "exit 0" [ "$CODE" = 0 ]
ok "sudo was never called" lacks "$CALLS" '^sudo'
ok "the question was skipped" has "$T/out" 'not asked'
ok "wg-quick up ran directly, no systemctl for WireGuard" sh -c "grep -q 'wg-quick up' '$CALLS' && ! grep -q 'systemctl enable' '$CALLS'"
ok "warning that it will not restart at boot" has "$T/out" 'will NOT restart at boot'
ok "helper started in the background with run, port and bind" sh -c "sleep 1; grep -q 'run --state-dir .* --port 9101 --bind 10.77.0.2 --heartbeat-seconds 5' '$AGENT_LOG' && test -s '$J/state/agent.pid'"
ok "enroll ran before run, token mode 600, token removed" sh -c "head -n 1 '$AGENT_LOG' | grep -q '^enroll --root http://10.77.0.1:9102 --name far-pc --enrollment-token-file .*/state/enroll.token --state-dir' && grep -q 'tokenmode 600' '$AGENT_LOG' && test ! -e '$J/state/enroll.token'"
HOME="$T/home" PATH="$BIN:$SYSTEM_PATH" CALLS="$CALLS" AS_ROOT="$AS_ROOT" sh "$J/leave.sh" > "$T/leave.out" 2>&1
ok "leave removes everything, without sudo" sh -c "grep -q 'has left' '$T/leave.out' && test ! -e '$J' && test ! -e '$WG_DIR/metaservice.conf' && ! grep -q '^sudo' '$CALLS'"
finish_world

echo "== no terminal and no JOIN_SHARE_YES: stops, changes nothing"
new_world Linux x86_64; install_tools_already; start_hub
TTY_FILE=/nonexistent; join approve-notty linux x86_64 ""; unset TTY_FILE
ok "plain message" sh -c "[ $CODE != 0 ] && grep -q 'set JOIN_SHARE_YES=1' '$T/out'"
ok "nothing ran" sh -c "! grep -q '^sudo\|register' '$CALLS' '$T/hub/hub.log' && test ! -e '$T/home/.metaservice-join'"
finish_world

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
