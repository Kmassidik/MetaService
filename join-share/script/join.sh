#!/bin/sh
# Joins this computer to a MetaService panel over WireGuard. Served by the hub with the four values below filled in.
# Read it before you run it: curl -fsSL "<address>" -o join.sh ; less join.sh ; sh join.sh
# Everything is in functions and main runs last, so a program that reads stdin cannot eat the rest of this file when it is piped into sh.
set -eu

LINK='@LINK@'
PUBLIC_URL='@PUBLIC_URL@'
WANT_OS='@OS@'
WANT_CPU='@CPU@'

JOIN_HOME=${JOIN_HOME:-${JOIN_SHARE_HOME:-$HOME/.metaservice-join}}
JOIN_TTY=${JOIN_TTY:-/dev/tty}
JOIN_IFACE=${JOIN_IFACE:-metaservice}
JOIN_WG_DIR=${JOIN_WG_DIR:-/etc/wireguard}
JOIN_DAEMON_DIR=${JOIN_DAEMON_DIR:-/Library/LaunchDaemons}
JOIN_UNIT_DIR=${JOIN_UNIT_DIR:-$HOME/.config/systemd/user}
JOIN_AGENT_DIR=${JOIN_AGENT_DIR:-$HOME/Library/LaunchAgents}
JOIN_SYSTEMD_DIR=${JOIN_SYSTEMD_DIR:-/run/systemd/system}
JOIN_TUN=${JOIN_TUN:-/dev/net/tun}
JOIN_POLL_SECONDS=${JOIN_POLL_SECONDS:-3}
JOIN_POLL_MAX=${JOIN_POLL_MAX:-300}
JOIN_ENROLL_TRIES=${JOIN_ENROLL_TRIES:-5}
HEARTBEAT_SECONDS=5
SERVICE_LABEL='io.metaservice.join'
WG_TMP="$JOIN_HOME/wg.conf.tmp"
PLIST_TMP="$JOIN_HOME/wg.plist.tmp"
BIN="$JOIN_HOME/bin/metaservice-agent"
STATE="$JOIN_HOME/state"

# ---- small tools -------------------------------------------------------------------------------

say() { printf '%s\n' "$*"; }
fail() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
indent() { sed 's/^/    /'; }
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
valid() { printf '%s' "$2" | grep -Eq "^$1\$"; }
need() { valid "$2" "$3" || fail "the hub's answer has an unexpected $1, so nothing was installed from it."; }

# The replies are small and flat, so a field is read with sed. Keys are unique in a reply; a string or a whole number is returned, or nothing.
json_get() {
  flat=$(printf '%s' "$1" | tr -d '\n')
  found=$(printf '%s' "$flat" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$found" ] || found=$(printf '%s' "$flat" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  printf '%s' "$found"
}

split_reply() {
  HTTP_CODE=$(printf '%s' "$out" | tail -n 1)
  HTTP_BODY=$(printf '%s' "$out" | sed '$d')
}
http_get() {
  out=$(curl -sS -m 30 -w '\n%{http_code}' "$1" 2>/dev/null) || out=$(printf '\n000')
  split_reply
}
http_post() {
  out=$(curl -sS -m 30 -H 'Content-Type: application/json' -d "$2" -w '\n%{http_code}' "$1" 2>/dev/null) || out=$(printf '\n000')
  split_reply
}

# Runs a block as root with one sudo. The script never reads a password: sudo asks on the terminal itself.
# As root already (a container, for example) the block runs directly and sudo is never called.
is_root() { [ "$(id -u)" = 0 ]; }
run_root() {
  block="set -eu; PATH=$(shq "$PATH"); export PATH; $1"
  is_root && { sh -c "$block"; return; }
  sudo sh -c "$block"
}
remember_sudo() {
  is_root && return 0
  have sudo || fail "this needs root and sudo is not installed. Run this as root, or install sudo."
  sudo -v
}
# A user service needs a user bus; a system service needs systemd as pid 1. Without them the script falls back and says so.
user_systemd_usable() { have systemctl && systemctl --user show-environment >/dev/null 2>&1; }
system_systemd_usable() { have systemctl && [ -d "$JOIN_SYSTEMD_DIR" ]; }

big_code() {
  printf '%s' "$1" | awk '
    BEGIN {
      font[0] = "###,# #,# #,# #,###"; font[1] = " # ,## , # , # ,###"; font[2] = "###,  #,###,#  ,###"
      font[3] = "###,  #,###,  #,###"; font[4] = "# #,# #,###,  #,  #"; font[5] = "###,#  ,###,  #,###"
      font[6] = "###,#  ,###,# #,###"; font[7] = "###,  #,  #,  #,  #"; font[8] = "###,# #,###,# #,###"
      font[9] = "###,# #,###,  #,###"
    }
    { for (row = 1; row <= 5; row++) {
        line = "    "
        for (i = 1; i <= length($0); i++) { split(font[substr($0, i, 1)], part, ","); line = line part[row] "  " }
        print line } }'
}

# ---- what this machine is ----------------------------------------------------------------------

check_settings() {
  case "$LINK$PUBLIC_URL$WANT_OS$WANT_CPU" in
    *@*) fail "this script was not filled in by the hub. Get the command again from the admin page." ;;
  esac
  valid '[A-Za-z0-9_./-]+' "$JOIN_HOME" || fail "JOIN_HOME may only have letters, digits and _ . / -"
  have curl || fail "curl is needed."
}

detect_machine() {
  case "$(uname -s)" in
    Darwin) MY_OS=mac ;;
    Linux) MY_OS=linux ;;
    *) MY_OS=$(uname -s) ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) MY_CPU=arm64 ;;
    x86_64 | amd64) MY_CPU=x86_64 ;;
    *) MY_CPU=$(uname -m) ;;
  esac
  [ "$MY_OS" = "$WANT_OS" ] || fail "you chose $WANT_OS on the page, but this computer is $MY_OS. Choose $MY_OS there and run the new command."
  [ "$MY_CPU" = "$WANT_CPU" ] || fail "you chose $WANT_CPU on the page, but this computer is $MY_CPU. Choose $MY_CPU there and run the new command."
  case "$MY_OS" in
    mac) ENGINE=${JOIN_ENGINE:-apple} ;;
    *) ENGINE=${JOIN_ENGINE:-incus} ;;
  esac
}

stop_if_joined() {
  [ -f "$JOIN_HOME/joined.env" ] || return 0
  say "This computer is already joined (state in $JOIN_HOME). Nothing was changed."
  say "To leave: sh $JOIN_HOME/leave.sh"
  exit 0
}

half() {
  value=$(( $1 / 2 ))
  [ "$value" -ge 1 ] || value=1
  printf '%s' "$value"
}

# What this computer offers by default: half of its cores, memory and free disk. The environment can set exact numbers.
detect_share() {
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
  if [ "$MY_OS" = mac ]; then ram=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 2147483648) / 1048576 ))
  else ram=$(awk '/^MemTotal/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null || echo 2048); fi
  disk=$(df -Pk "$HOME" 2>/dev/null | awk 'NR == 2 { print int($4 / 1048576) }')
  SHARE_CORES=${JOIN_SHARE_CORES:-$(half "$cores")}
  SHARE_RAM_MB=${JOIN_SHARE_RAM_MB:-$(half "${ram:-2048}")}
  SHARE_DISK_GB=${JOIN_SHARE_DISK_GB:-$(half "${disk:-20}")}
  valid '[0-9]+' "$SHARE_CORES$SHARE_RAM_MB$SHARE_DISK_GB" || fail "the share numbers (JOIN_SHARE_*) must be whole numbers."
}

# ---- the check list and the root block ---------------------------------------------------------

row() { printf '  %-9s %s\n' "[$1]" "$2"; }
report() { if "$@"; then row found "$LABEL"; else row missing "$LABEL"; return 1; fi; }

kernel_has_wireguard() { [ -d /sys/module/wireguard ] || modinfo wireguard >/dev/null 2>&1 || modprobe -n wireguard >/dev/null 2>&1; }
linger_is_on() { ! have loginctl || loginctl show-user "$(id -un)" -p Linger 2>/dev/null | grep -q 'Linger=yes'; }
has_helper() { [ -x "$BIN" ]; }

check_machine() {
  say "What is on this computer:"
  MISSING_WG=no
  LABEL="wg"; report have wg || MISSING_WG=yes
  LABEL="wg-quick"; report have wg-quick || MISSING_WG=yes
  LABEL="curl"; report have curl
  LABEL="the MetaService helper"; report has_helper || true
  check_platform_items
}

check_platform_items() {
  if [ "$MY_OS" = mac ]; then
    LABEL="wireguard-go"; report have wireguard-go || MISSING_WG=yes
    LABEL="Apple container (for virtual machines; the helper reports it if it is not ready)"
    [ "$ENGINE" != apple ] || report have container || true
    return 0
  fi
  check_linux_wireguard
  LABEL="Incus"; [ "$ENGINE" != incus ] || report have incus || NEED_INCUS=yes
  LABEL="start-at-boot for your user (linger)"; report linger_is_on || NEED_LINGER=yes
}

# One line for WireGuard on Linux: the kernel module, else userspace (wg-quick falls back to wireguard-go on its own), else it must be installed.
check_linux_wireguard() {
  WG_MODE=kernel
  kernel_has_wireguard && { row found "WireGuard (kernel)"; return 0; }
  WG_MODE=userspace
  [ -e "$JOIN_TUN" ] || fail "this kernel has no WireGuard module and $JOIN_TUN is missing, so userspace WireGuard cannot work either. In a container, start it with the tun device."
  have wireguard-go && { row found "WireGuard (userspace, wireguard-go)"; return 0; }
  row missing "WireGuard (no kernel module and no wireguard-go)"
  NEED_GO=yes
}

# The package step: Homebrew runs as you on a Mac; on Linux it is the first root block.
plan_packages() {
  BLOCK_PACKAGES=""
  USER_PACKAGES=""
  [ "$MISSING_WG" = yes ] || [ "$NEED_GO" = yes ] || [ "$NEED_INCUS" = yes ] || return 0
  if [ "$MY_OS" = mac ]; then
    have brew || fail "Homebrew (brew) is needed to install WireGuard on a Mac. Install it, then run this again."
    USER_PACKAGES="brew install wireguard-tools wireguard-go"
    return 0
  fi
  packages=""
  [ "$MISSING_WG" != yes ] || packages=" wireguard-tools"
  [ "$NEED_GO" != yes ] || packages="$packages wireguard-go"
  [ "$NEED_INCUS" != yes ] || packages="$packages incus"
  if have dnf; then installer="dnf install -y"
  elif have apt-get; then installer="apt-get install -y"
  else fail "WireGuard packages are missing and neither dnf nor apt-get was found. Install them, then run this again."; fi
  [ "$NEED_GO" != yes ] || [ "$installer" != "dnf install -y" ] || fail "this kernel has no WireGuard module, and dnf has no userspace WireGuard (wireguard-go) to fall back on. Use a kernel with WireGuard, then run this again."
  [ "$NEED_INCUS" != yes ] || package_known "$installer" incus || fail "the package manager has no package named incus. Install Incus yourself, then run this again (or set JOIN_ENGINE=simulated to join without virtual machines)."
  BLOCK_PACKAGES="$installer$packages"
}

package_known() {
  case "$1" in
    dnf*) dnf info "$2" >/dev/null 2>&1 ;;
    *) apt-cache show "$2" >/dev/null 2>&1 ;;
  esac
}

append_block() {
  [ -n "$2" ] || { printf '%s' "$1"; return 0; }
  [ -n "$1" ] || { printf '%s' "$2"; return 0; }
  printf '%s\n%s' "$1" "$2"
}

in_incus_group() { id -nG | tr ' ' '\n' | grep -qx incus-admin; }
incus_is_configured() { have incus && [ -n "$(incus storage list --format csv 2>/dev/null)" ]; }

# Incus in the root block: started at boot, set up once (never again if it already has a storage pool), and the user may use it.
plan_incus_steps() {
  BLOCK_INCUS=""
  ADD_GROUP=no
  [ "$ENGINE" = incus ] || return 0
  is_root || in_incus_group || ADD_GROUP=yes
  [ "$NEED_INCUS" != yes ] || ! system_systemd_usable || BLOCK_INCUS="systemctl enable --now incus"
  incus_is_configured || BLOCK_INCUS=$(append_block "$BLOCK_INCUS" '[ -n "$(incus storage list --format csv 2>/dev/null)" ] || incus admin init --minimal')
  [ "$ADD_GROUP" != yes ] || BLOCK_INCUS=$(append_block "$BLOCK_INCUS" "usermod -aG incus-admin $(shq "$(id -un)")")
}

plan_linux_block() {
  plan_incus_steps
  BLOCK_PACKAGES=$(append_block "$BLOCK_PACKAGES" "$BLOCK_INCUS")
  BOOT_COMMANDS="wg-quick down $(shq "$WG_CONF") 2>/dev/null || true
wg-quick up $(shq "$WG_CONF")"
  WG_BOOT=none
  if system_systemd_usable; then
    WG_BOOT=systemd
    BOOT_COMMANDS="systemctl enable $(shq "wg-quick@$JOIN_IFACE")
systemctl restart $(shq "wg-quick@$JOIN_IFACE")"
  fi
  user_systemd_usable || NEED_LINGER=no
  [ "$NEED_LINGER" != yes ] || BLOCK_PACKAGES=$(append_block "$BLOCK_PACKAGES" "loginctl enable-linger $(shq "$(id -un)")")
  BLOCK_UP="mkdir -p $(shq "$JOIN_WG_DIR")
install -m 600 $(shq "$WG_TMP") $(shq "$WG_CONF")
rm -f $(shq "$WG_TMP")
$BOOT_COMMANDS"
}

plan_mac_block() {
  BLOCK_UP="mkdir -p $(shq "$JOIN_WG_DIR")
install -m 600 $(shq "$WG_TMP") $(shq "$WG_CONF")
rm -f $(shq "$WG_TMP")
wg-quick down $(shq "$WG_CONF") 2>/dev/null || true
wg-quick up $(shq "$WG_CONF")
mkdir -p $(shq "$JOIN_DAEMON_DIR")
install -m 644 $(shq "$PLIST_TMP") $(shq "$WG_PLIST")
rm -f $(shq "$PLIST_TMP")"
}

plan_root_blocks() {
  WG_CONF="$JOIN_WG_DIR/$JOIN_IFACE.conf"
  WG_PLIST="$JOIN_DAEMON_DIR/$SERVICE_LABEL.wg.plist"
  if [ "$MY_OS" = mac ]; then plan_mac_block; else plan_linux_block; fi
}

print_plan() {
  say ""
  say "This will join this computer to the MetaService panel at $PUBLIC_URL. In order:"
  say "  1. Install what is missing (see the list above)."
  say "  2. Make a WireGuard key pair here. The private key never leaves this computer."
  say "  3. Ask the hub to let it join and show a 6-digit code. You give that code to the admin, who approves."
  say "  4. When approved: set up the WireGuard connection, download the helper (its checksum is verified),"
  say "     enroll it, and start it so it runs at boot as you, not as root."
  say "  5. Leave a script, $JOIN_HOME/leave.sh, that undoes all of it."
  say ""
  if is_root; then say "These commands run as root (you are root, so no sudo):"
  else say "These commands run as root with sudo. sudo asks for your password once, on this terminal; this script never sees it:"; fi
  [ -z "$USER_PACKAGES" ] || say "  (as you, not root)  $USER_PACKAGES"
  [ -z "$BLOCK_PACKAGES" ] || { printf '%s\n' "$BLOCK_PACKAGES" | indent; }
  printf '%s\n' "$BLOCK_UP" | indent
  say ""
}

confirm() {
  [ "${JOIN_SHARE_YES:-}" != 1 ] || { say "Continue? yes (JOIN_SHARE_YES=1, not asked)"; return 0; }
  printf 'Continue? [y/N] '
  answer=n
  IFS= read -r answer < "$JOIN_TTY" || fail "no terminal to ask; set JOIN_SHARE_YES=1 to continue without asking."
  case "$answer" in
    y | Y) return 0 ;;
    *) say "Not continued. Nothing was changed."; exit 0 ;;
  esac
}

# ---- doing it ----------------------------------------------------------------------------------

prepare_root() {
  PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
  [ -z "$USER_PACKAGES" ] || $USER_PACKAGES
  remember_sudo
  [ -z "$BLOCK_PACKAGES" ] || run_root "$BLOCK_PACKAGES"
  have wg && have wg-quick || fail "WireGuard tools are still missing after the install."
  [ "$NEED_GO" != yes ] || have wireguard-go || fail "wireguard-go is still missing after the install."
}

make_keys() {
  mkdir -p "$JOIN_HOME/bin" "$STATE"
  chmod 700 "$JOIN_HOME"
  [ -s "$JOIN_HOME/wg.key" ] || { umask 077; wg genkey > "$JOIN_HOME/wg.key"; }
  wg pubkey < "$JOIN_HOME/wg.key" > "$JOIN_HOME/wg.pub"
  PUBLIC_KEY=$(cat "$JOIN_HOME/wg.pub")
}

register() {
  host=$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9._-')
  body=$(printf '{"wg_public_key":"%s","os":"%s","cpu":"%s","hostname":"%s","share":{"cores":%s,"ram_mb":%s,"disk_gb":%s}}' \
    "$PUBLIC_KEY" "$MY_OS" "$MY_CPU" "${host:-unknown}" "$SHARE_CORES" "$SHARE_RAM_MB" "$SHARE_DISK_GB")
  http_post "$PUBLIC_URL/j/$LINK/register" "$body"
  [ "$HTTP_CODE" != 404 ] || fail "this link is unknown, expired or already used. Get a new command from the admin page."
  [ "$HTTP_CODE" = 200 ] || fail "the hub did not accept the join request (HTTP $HTTP_CODE)."
  PENDING=$(json_get "$HTTP_BODY" pending)
  SECRET=$(json_get "$HTTP_BODY" secret)
  CODE=$(json_get "$HTTP_BODY" code)
  valid '[A-Za-z0-9_-]+' "$PENDING" && valid '[A-Za-z0-9_-]+' "$SECRET" && valid '[0-9]{6}' "$CODE" || fail "the hub's answer to the join request was not understood."
}

show_code() {
  say ""
  say "Tell the admin this code. They type it on the admin page and press Approve:"
  say ""
  big_code "$CODE"
  say ""
  say "In plain digits (to read aloud or copy): $CODE"
  say ""
  say "Waiting for the approval (up to $(( JOIN_POLL_MAX * JOIN_POLL_SECONDS / 60 )) minutes). Press Ctrl-C to cancel; nothing is joined until it is approved."
}

wait_for_approval() {
  tries=0
  while [ "$tries" -lt "$JOIN_POLL_MAX" ]; do
    tries=$(( tries + 1 ))
    http_get "$PUBLIC_URL/j/$LINK/status?pending=$PENDING&secret=$SECRET"
    state=$(json_get "$HTTP_BODY" state)
    case "$state" in
      approved) STATUS=$HTTP_BODY; return 0 ;;
      refused) fail "the admin refused this computer. Nothing was joined." ;;
      expired) fail "the request expired before it was approved. Get a new command from the admin page." ;;
    esac
    # Keeps the sudo password remembered while waiting; if sudo forgets it anyway, it asks once more later.
    is_root || sudo -n -v >/dev/null 2>&1 || true
    sleep "$JOIN_POLL_SECONDS"
  done
  fail "no answer in time. Get a new command from the admin page."
}

field() { json_get "$STATUS" "$1"; }

# The share after the admin lowered it comes with the approval (machine.share); the asked numbers stay when it is missing.
apply_granted_share() {
  granted=$(field ram_mb)
  ! valid '[1-9][0-9]*' "$granted" || SHARE_RAM_MB=$granted
  granted=$(field disk_gb)
  ! valid '[1-9][0-9]*' "$granted" || SHARE_DISK_GB=$granted
}

read_approval() {
  WG_ADDRESS=$(field address); HUB_KEY=$(field hub_public_key); ENDPOINT=$(field endpoint); ALLOWED=$(field allowed_ips); KEEPALIVE=$(field keepalive)
  NAME=$(field name); TOKEN=$(field enrollment_token); PARENT_URL=$(field parent_url); HELPER_BIND=$(field helper_bind); HELPER_PORT=$(field helper_port)
  DOWNLOAD_URL=$(field url); DOWNLOAD_SHA=$(field sha256)
  need "address" '[0-9.]+/[0-9]+' "$WG_ADDRESS"
  need "hub key" '[A-Za-z0-9+/]{43}=' "$HUB_KEY"
  need "endpoint" '[A-Za-z0-9._-]+:[0-9]+' "$ENDPOINT"
  need "allowed addresses" '[0-9./,]+' "$ALLOWED"
  need "keepalive" '[0-9]+' "$KEEPALIVE"
  need "machine name" '[a-z0-9-]+' "$NAME"
  need "enrollment token" '[A-Za-z0-9._-]+' "$TOKEN"
  need "parent address" 'https?://[A-Za-z0-9.:_-]+' "$PARENT_URL"
  need "helper address" '[0-9.]+' "$HELPER_BIND"
  need "helper port" '[0-9]+' "$HELPER_PORT"
  need "download address" 'https?://[A-Za-z0-9.:/_?=&%-]+' "$DOWNLOAD_URL"
  need "checksum" '[0-9a-fA-F]{64}' "$DOWNLOAD_SHA"
  apply_granted_share
  (umask 077; printf '%s' "$TOKEN" > "$STATE/enroll.token")
}

sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{ print $1 }'; return 0; fi
  shasum -a 256 "$1" | awk '{ print $1 }'
}

download_helper() {
  part="$BIN.part"
  curl -fsS -m 600 -o "$part" "$DOWNLOAD_URL" || { rm -f "$part"; fail "the helper could not be downloaded. Nothing was run."; }
  got=$(sha256_of "$part")
  [ "$got" = "$(printf '%s' "$DOWNLOAD_SHA" | tr 'A-F' 'a-f')" ] || { rm -f "$part" "$STATE/enroll.token"; fail "the helper's checksum does not match, so it was deleted and nothing was run."; }
  chmod 700 "$part"
  mv "$part" "$BIN"
}

write_wg_config() {
  (umask 077
   printf '[Interface]\nPrivateKey = %s\nAddress = %s\n\n[Peer]\nPublicKey = %s\nEndpoint = %s\nAllowedIPs = %s\nPersistentKeepalive = %s\n' \
     "$(cat "$JOIN_HOME/wg.key")" "$WG_ADDRESS" "$HUB_KEY" "$ENDPOINT" "$ALLOWED" "$KEEPALIVE" > "$WG_TMP")
  [ "$MY_OS" = mac ] || return 0
  cat > "$PLIST_TMP" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>Label</key><string>$SERVICE_LABEL.wg</string>
<key>ProgramArguments</key><array><string>$(command -v wg-quick)</string><string>up</string><string>$WG_CONF</string></array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$(dirname "$(command -v wg-quick)"):/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
<key>RunAtLoad</key><true/>
</dict></plist>
EOF
}

connect() {
  write_wg_config
  run_root "$BLOCK_UP"
}

enroll_helper() {
  attempt=0
  while [ "$attempt" -lt "$JOIN_ENROLL_TRIES" ]; do
    attempt=$(( attempt + 1 ))
    "$BIN" enroll --root "$PARENT_URL" --name "$NAME" --enrollment-token-file "$STATE/enroll.token" --state-dir "$STATE" && break
    [ "$attempt" -lt "$JOIN_ENROLL_TRIES" ] || fail "the helper could not enroll with the panel. Run $JOIN_HOME/leave.sh and ask for a new command."
    sleep "$JOIN_POLL_SECONDS"
  done
  rm -f "$STATE/enroll.token"
}

helper_words() {
  printf 'run --state-dir %s --engine %s --port %s --bind %s --heartbeat-seconds %s --ram-allowance-mb %s --disk-allowance-gb %s' \
    "$STATE" "$ENGINE" "$HELPER_PORT" "$HELPER_BIND" "$HEARTBEAT_SECONDS" "$SHARE_RAM_MB" "$SHARE_DISK_GB"
}

# Just added to the incus-admin group, the running session does not have it yet: sg starts the helper with the group, so no new login is needed.
wrap_in_group() { [ "$ENGINE" = incus ] && ! is_root && ! in_incus_group; }
helper_exec() {
  wrap_in_group || { printf '%s %s' "$BIN" "$(helper_words)"; return 0; }
  printf "%s incus-admin -c '%s %s'" "$(command -v sg)" "$BIN" "$(helper_words)"
}

start_linux_service() {
  user_systemd_usable || { start_background; return; }
  mkdir -p "$JOIN_UNIT_DIR"
  UNIT_FILE="$JOIN_UNIT_DIR/$SERVICE_LABEL.service"
  printf '[Unit]\nDescription=MetaService helper (joined machine)\nAfter=network-online.target\n\n[Service]\nExecStart=%s\nRestart=always\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n' \
    "$(helper_exec)" > "$UNIT_FILE"
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_LABEL.service"
  systemctl --user restart "$SERVICE_LABEL.service"
}

# No systemd for this user: the helper runs in the background now and will not come back after a reboot.
start_background() {
  UNIT_FILE=""
  mkdir -p "$JOIN_HOME/logs"
  if [ -f "$STATE/agent.pid" ]; then kill "$(cat "$STATE/agent.pid")" 2>/dev/null || true; fi
  nohup sh -c "exec $(helper_exec)" >> "$JOIN_HOME/logs/agent.log" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$STATE/agent.pid"
  say "Warning: systemd is not available for your user, so the helper runs in the background and will NOT restart at boot."
}

start_mac_service() {
  mkdir -p "$JOIN_AGENT_DIR" "$JOIN_HOME/logs"
  UNIT_FILE="$JOIN_AGENT_DIR/$SERVICE_LABEL.plist"
  words=""
  for word in $(helper_words); do words="$words<string>$word</string>"; done
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n<key>Label</key><string>%s</string>\n<key>ProgramArguments</key><array><string>%s</string>%s</array>\n<key>RunAtLoad</key><true/>\n<key>KeepAlive</key><true/>\n<key>StandardOutPath</key><string>%s/logs/agent.log</string>\n<key>StandardErrorPath</key><string>%s/logs/agent.log</string>\n</dict></plist>\n' \
    "$SERVICE_LABEL" "$BIN" "$words" "$JOIN_HOME" "$JOIN_HOME" > "$UNIT_FILE"
  target="gui/$(id -u)"
  launchctl bootout "$target/$SERVICE_LABEL" 2>/dev/null || true
  launchctl bootstrap "$target" "$UNIT_FILE"
}

# ---- leaving -----------------------------------------------------------------------------------

write_leave() {
  {
    printf 'MS_OS=%s\nMS_NAME=%s\nMS_HOME=%s\nMS_UNIT=%s\nMS_LABEL=%s\nMS_CONF=%s\nMS_WG_PLIST=%s\nMS_IFACE=%s\nMS_UID=%s\nMS_BOOT=%s\n' \
      "$(shq "$MY_OS")" "$(shq "$NAME")" "$(shq "$JOIN_HOME")" "$(shq "$UNIT_FILE")" "$(shq "$SERVICE_LABEL")" "$(shq "$WG_CONF")" "$(shq "$WG_PLIST")" "$(shq "$JOIN_IFACE")" "$(id -u)" "$(shq "${WG_BOOT:-launchd}")"
  } > "$JOIN_HOME/joined.env"
  cat > "$JOIN_HOME/leave.sh" <<'EOF'
#!/bin/sh
# Undoes the join: stops the helper, takes WireGuard down, removes the start-at-boot entries, the helper and this folder.
# The WireGuard tools stay installed. Ask the admin to remove this machine from the panel too.
set -eu
. "$(dirname "$0")/joined.env"
echo "Leaving MetaService as $MS_NAME. These commands run as root (sudo asks for your password):"
SUDO=sudo
[ "$MS_UID" != 0 ] || SUDO=
case "$MS_OS-$MS_BOOT" in
  mac-*) ROOT="wg-quick down '$MS_CONF' || true; rm -f '$MS_CONF' '$MS_WG_PLIST'"; launchctl bootout "gui/$MS_UID/$MS_LABEL" 2>/dev/null || true ;;
  linux-systemd) ROOT="systemctl disable --now 'wg-quick@$MS_IFACE' || true; rm -f '$MS_CONF'" ;;
  *) ROOT="wg-quick down '$MS_CONF' || true; rm -f '$MS_CONF'" ;;
esac
if [ -f "$MS_HOME/state/agent.pid" ]; then kill "$(cat "$MS_HOME/state/agent.pid")" 2>/dev/null || true; fi
if [ -n "$MS_UNIT" ] && [ "$MS_OS" = linux ]; then systemctl --user disable --now "$MS_LABEL.service" || true; fi
printf '    %s\n' "$ROOT"
$SUDO sh -c "PATH='$PATH'; export PATH; $ROOT"
[ -z "$MS_UNIT" ] || rm -f "$MS_UNIT"
[ -z "$MS_UNIT" ] || [ "$MS_OS" = mac ] || systemctl --user daemon-reload || true
rm -rf "$MS_HOME"
echo "Done. This computer has left."
EOF
  chmod 700 "$JOIN_HOME/leave.sh"
}

main() {
  trap 'rm -f "$WG_TMP" "$PLIST_TMP"' EXIT
  check_settings
  detect_machine
  stop_if_joined
  detect_share
  NEED_LINGER=no
  NEED_GO=no
  NEED_INCUS=no
  check_machine
  plan_packages
  plan_root_blocks
  print_plan
  confirm
  prepare_root
  make_keys
  register
  show_code
  wait_for_approval
  read_approval
  download_helper
  connect
  enroll_helper
  if [ "$MY_OS" = mac ]; then start_mac_service; else start_linux_service; fi
  write_leave
  say ""
  say "Joined as $NAME. It shows as online in the panel in a few seconds."
  say "To leave later: sh $JOIN_HOME/leave.sh"
}

main "$@"
