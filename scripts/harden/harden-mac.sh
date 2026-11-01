#!/usr/bin/env bash
# Hardens a Mac that MetaService manages (Mac Mini, Mac Studio). You run it yourself with sudo.
# It never reboots, never changes software updates or FileVault, and never touches the MetaService
# helper or parent. Screen Sharing is left alone unless you ask with --screen-sharing-off.
#
#   harden-mac.sh [check]                      read-only table: what is set now, what apply would change
#   sudo harden-mac.sh apply --confirm-key-login [--extra-users "bob"] [--screen-sharing-off]
#   sudo harden-mac.sh confirm                 keep the changes (cancels the automatic rollback)
#   sudo harden-mac.sh rollback                put back what the last apply changed
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harden-common.sh
. "$SCRIPT_DIR/harden-common.sh"

# ---- settings (override with environment variables) ----------------------------------------
EXTRA_ALLOWED_USERS="${EXTRA_ALLOWED_USERS:-}"
PUBLIC_ADDRESS="${PUBLIC_ADDRESS:-<public-address>}"
PUBLIC_PORT="${PUBLIC_PORT:-<public-port>}"
# Programs that must stay reachable through the firewall, looked up in the folders below.
FIREWALL_ALLOW_NAMES="${FIREWALL_ALLOW_NAMES:-metaservice-root metaservice-agent cloudflared wireguard-go}"
FIREWALL_SEARCH_DIRS="${FIREWALL_SEARCH_DIRS:-/opt/homebrew/bin /usr/local/bin /usr/local/sbin /opt/metaservice/bin}"
# Extra absolute paths to allow, space separated (no spaces inside a path).
FIREWALL_EXTRA_APPS="${FIREWALL_EXTRA_APPS:-}"

SSH_DROPIN_NAME="00-metaservice-hardening.conf"   # "00" so sshd reads it first (sshd keeps the first value)
SSH_MAX_AUTH_TRIES=3
SSH_LOGIN_GRACE_SECONDS=20
SOCKETFILTERFW_PATH="/usr/libexec/ApplicationFirewall/socketfilterfw"
SCREEN_SHARING_SERVICE="system/com.apple.screensharing"
SCREEN_SHARING_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"
KICKSTART="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
APP_PATH_PATTERN='^/[A-Za-z0-9_./+-]+$'           # no spaces or odd characters in paths we pass to commands
REVERT_MARKER_NAME="metaservice-harden-revert"    # shows in `ps`, so confirm kills only our own timer

STATE_DIR="$(host_path /var/db/metaservice-harden)"
SSH_DIR="$(host_path /etc/ssh)"
SSH_DROPIN="$SSH_DIR/sshd_config.d/$SSH_DROPIN_NAME"
PENDING_MARKER="$STATE_DIR/revert-pending"
REVERT_PID_FILE="$STATE_DIR/revert.pid"
SCREEN_SHARING_OFF=0
SOCKETFILTERFW="$SOCKETFILTERFW_PATH"

# ---- machine detection -----------------------------------------------------------------------

lookup_home() { dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'; }

detect_machine() {
  local system version
  system="${HARDEN_FAKE_UNAME:-$(uname -s)}"
  [ "$system" = Darwin ] || refuse "This script is for macOS. This machine says: '$system'. Nothing was changed."
  version="$(sys_out sw_vers -productVersion || true)"
  note "Machine: macOS ${version:-unknown} ($(uname -m)). Supported."
}

# ---- sshd ------------------------------------------------------------------------------------

ssh_dropin_content() {
  cat <<EOF
# Managed by MetaService harden-mac.sh. Remove with: sudo harden-mac.sh rollback
# Named 00-* because sshd keeps the FIRST value it reads (macOS ships 100-macos.conf).
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $1
MaxAuthTries $SSH_MAX_AUTH_TRIES
LoginGraceTime $SSH_LOGIN_GRACE_SECONDS
EOF
}

# The drop-in is only read if the main config includes the folder.
require_ssh_include() {
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$SSH_DIR/sshd_config" \
    || refuse "$SSH_DIR/sshd_config does not include sshd_config.d, so the drop-in would be ignored."
}

verify_effective_ssh() {
  local user_list="$1" effective option
  effective="$(sys_out sshd -T | tr '[:upper:]' '[:lower:]')"
  [ -n "$effective" ] || refuse "sshd -T printed nothing, so I cannot prove the new settings are active."
  for option in "passwordauthentication no" "kbdinteractiveauthentication no" "permitrootlogin no" "allowusers $user_list"; do
    printf '%s\n' "$effective" | grep -Fxq "$option" \
      || refuse "sshd would still use a different value than '$option' (another file wins?). Undoing."
  done
}

# macOS starts a fresh sshd for every connection, so there is nothing to reload: the next login
# reads the new file. Existing sessions keep running. That is also why 'sshd -t' must pass first.
step_ssh() {
  local user_list="$1"
  note "[SSH] key-only login drop-in"
  install_managed_file "$SSH_DROPIN" 644 "$(ssh_dropin_content "$user_list")"
  [ "$FILE_CHANGED" = 1 ] || return 0
  sys sshd -t || refuse "sshd -t rejected the new configuration. Undoing."
  verify_effective_ssh "$user_list"
  note "  active for the next login (no reload needed on macOS)."
}

# ---- application firewall --------------------------------------------------------------------

fw() { sys "$SOCKETFILTERFW" "$@"; }
fw_out() { sys_out "$SOCKETFILTERFW" "$@"; }

fw_global_on() { fw_out --getglobalstate | grep -Eiq 'enabled|State = [12]'; }
fw_stealth_on() { fw_out --getstealthmode | grep -Eiq 'is on|mode enabled'; }
fw_builtin_signed_on() { fw_out --getallowsigned | grep -q 'built-in signed software ENABLED'; }
fw_downloaded_signed_on() { fw_out --getallowsigned | grep -q 'downloaded signed software ENABLED'; }
fw_knows_app() { fw_out --listapps | grep -Fq "$1"; }

# Prints the full path of each allow-listed program that exists on this machine.
firewall_apps_found() {
  local name dir path
  for name in $FIREWALL_ALLOW_NAMES; do
    for dir in $FIREWALL_SEARCH_DIRS; do
      [ -x "$(host_path "$dir/$name")" ] && printf '%s\n' "$dir/$name"
    done
  done
  for path in $FIREWALL_EXTRA_APPS; do
    [ -x "$(host_path "$path")" ] && printf '%s\n' "$path"
  done
  return 0
}

allow_app() {
  local path="$1"
  if ! printf '%s' "$path" | grep -Eq "$APP_PATH_PATTERN"; then
    warn "not adding '$path' to the firewall (unusual characters)"
    return 0
  fi
  if fw_knows_app "$path"; then
    note "  firewall already knows $path"
    return 0
  fi
  fw --add "$path"
  fw --unblockapp "$path"
  record_undo "$SOCKETFILTERFW --remove $path"
  CHANGES_MADE=1
  note "  allowed $path"
}

# Turns one firewall switch on and records how to put it back (only if it was off).
switch_on() {
  local label="$1" is_on_function="$2" on_flag="$3" off_flag="$4"
  if "$is_on_function"; then
    note "  $label already on"
    return 0
  fi
  fw "$on_flag" on
  record_undo "$SOCKETFILTERFW $off_flag off"
  CHANGES_MADE=1
  note "  $label turned on"
}

# Order matters: programs are allowed BEFORE the firewall turns on, so the helper never gets blocked.
step_firewall() {
  local app
  note "[firewall] application firewall, stealth mode, allow signed apps"
  while IFS= read -r app; do
    [ -z "$app" ] || allow_app "$app"
  done <<EOF
$(firewall_apps_found)
EOF
  switch_on "allow built-in signed software" fw_builtin_signed_on --setallowsigned --setallowsigned
  switch_on "allow downloaded signed software" fw_downloaded_signed_on --setallowsignedapp --setallowsignedapp
  switch_on "stealth mode" fw_stealth_on --setstealthmode --setstealthmode
  switch_on "firewall" fw_global_on --setglobalstate --setglobalstate
}

# ---- screen sharing (opt-in) -----------------------------------------------------------------

screen_sharing_state() {
  local line
  line="$(sys_out launchctl print-disabled system | grep 'com.apple.screensharing' || true)"
  case "$line" in
    *'=> enabled'* | *'=> false'*) printf 'on' ;;
    *'=> disabled'* | *'=> true'*) printf 'off' ;;
    *) printf 'unknown' ;;
  esac
}

remote_management_running() { [ -n "$(sys_out pgrep -x ARDAgent || true)" ]; }

step_screen_sharing() {
  note "[screen sharing] turning off Screen Sharing and Remote Management (you asked for this)"
  if [ "$(screen_sharing_state)" != off ]; then
    sys launchctl disable "$SCREEN_SHARING_SERVICE"
    sys launchctl bootout "$SCREEN_SHARING_SERVICE" || true
    record_undo "launchctl enable $SCREEN_SHARING_SERVICE"
    record_undo "launchctl bootstrap system $SCREEN_SHARING_PLIST"
    CHANGES_MADE=1
    note "  Screen Sharing off. rollback turns it back on."
  fi
  remote_management_running || return 0
  sys "$KICKSTART" -deactivate -stop
  CHANGES_MADE=1
  warn "Remote Management was switched off. rollback cannot restore it; turn it on again in System Settings > Sharing."
}

# ---- automatic rollback ----------------------------------------------------------------------

# A detached background job sleeps, then runs rollback. confirm kills it. A reboot also ends it.
schedule_revert() {
  local bin_dir="$STATE_DIR/bin" pid=0
  mkdir -p "$bin_dir"
  cp -p "$SCRIPT_DIR/harden-mac.sh" "$SCRIPT_DIR/harden-common.sh" "$bin_dir/"
  if is_dry; then
    printf 'detached-revert %s sleep=%s %s rollback --auto\n' "$REVERT_MARKER_NAME" "$REVERT_SECONDS" "$bin_dir/harden-mac.sh" >>"$CALL_LOG"
  else
    # shellcheck disable=SC2016  # $1 and $2 are for the inner sh, on purpose
    nohup sh -c 'sleep "$1"; exec "$2" rollback --auto' "$REVERT_MARKER_NAME" "$REVERT_SECONDS" "$bin_dir/harden-mac.sh" \
      </dev/null >/dev/null 2>&1 &
    pid=$!
  fi
  printf '%s\n' "$pid" >"$REVERT_PID_FILE"
  touch "$PENDING_MARKER"
  note "Automatic rollback scheduled in $((REVERT_SECONDS / 60)) minutes. Run 'sudo harden-mac.sh confirm' to keep the changes."
}

# Kills the timer, but only if the process really is ours (a recycled pid must never be killed).
cancel_revert() {
  local pid
  if [ -f "$REVERT_PID_FILE" ]; then
    pid="$(cat "$REVERT_PID_FILE")"
    if is_dry; then
      printf 'cancel-detached-revert %s\n' "$pid" >>"$CALL_LOG"
    elif ps -p "$pid" -o command= 2>/dev/null | grep -Fq "$REVERT_MARKER_NAME"; then
      kill "$pid"
    fi
  fi
  rm -f "$REVERT_PID_FILE" "$PENDING_MARKER"
}

# ---- messages --------------------------------------------------------------------------------

print_advice() {
  say ""
  say "Advice only (not done by this script):"
  say "  - Software update: macOS updates need a restart, and the MetaService parent and panel are down while it runs."
  say "    See what is offered with: softwareupdate --list   Then update from System Settings when nobody is using it."
  say "  - FileVault ($(sys_out fdesetup status | head -n 1 || true)): turning it on protects the disk, but after every restart"
  say "    someone must type the password at the Mac, so a remote reboot will not come back by itself. Decide with console access."
  say "  - Firewall warning: if a prompt asks whether to allow incoming connections for a helper, choose Allow."
  say "    To add one by hand:  sudo $SOCKETFILTERFW_PATH --add /path/to/program && sudo $SOCKETFILTERFW_PATH --unblockapp /path/to/program"
  say "    The helper (metaservice-root / metaservice-agent), cloudflared and wireguard-go are added automatically when found."
}

print_summary() {
  local user="$1"
  say ""
  say "=== Summary ==="
  say "Log file: $LOG_FILE"
  say "Backups:  $STATE_DIR"
  say ""
  say "Verify now (from ANOTHER terminal, do not close this one):"
  say "  ssh -o BatchMode=yes -p $PUBLIC_PORT $user@$PUBLIC_ADDRESS true                 # your key login must still work"
  say "  ssh -o BatchMode=yes -o PreferredAuthentications=password -o PubkeyAuthentication=no -p $PUBLIC_PORT $user@$PUBLIC_ADDRESS true"
  say "      -> must say: Permission denied (publickey)."
  say "On this Mac:"
  say "  sudo sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|allowusers)'"
  say "  $SOCKETFILTERFW_PATH --getglobalstate; $SOCKETFILTERFW_PATH --getstealthmode"
  say "  Then open the MetaService Security page: the machine's rows should turn green."
  say ""
  if [ "$CHANGES_MADE" = 1 ]; then
    say "NEXT: if the key login and the MetaService connection both work, run: sudo $0 confirm"
    say "If you do nothing, everything is rolled back automatically in $((REVERT_SECONDS / 60)) minutes."
    return 0
  fi
  say "Nothing needed changing. Everything was already in place."
}

# ---- commands --------------------------------------------------------------------------------

run_apply() {
  local user extras user_list
  require_root
  detect_machine
  user="$(invoking_user)"
  extras="$(validated_user_list "$EXTRA_ALLOWED_USERS")"
  user_list="$user${extras:+ $extras}"
  if [ -f "$PENDING_MARKER" ]; then
    refuse "The previous apply is still waiting. Run 'confirm' or 'rollback' first."
  fi
  require_ssh_include
  require_key_login_safe "$user"
  mkdir -p "$STATE_DIR"
  trap 'apply_exit_trap $?' EXIT
  log_line "apply started by $user"
  step_firewall
  [ "$SCREEN_SHARING_OFF" = 0 ] || step_screen_sharing
  step_ssh "$user_list"
  [ "$CHANGES_MADE" = 0 ] || schedule_revert
  APPLY_FINISHED=1
  trap - EXIT
  print_advice
  print_summary "$user"
}

# ---- check (read-only) -----------------------------------------------------------------------

on_off() { if "$@"; then printf 'on'; else printf 'off'; fi; }

check_ssh() {
  local files password dropin
  files="$(ls "$SSH_DIR"/sshd_config.d/*.conf 2>/dev/null || true) $SSH_DIR/sshd_config"
  # shellcheck disable=SC2086  # the file list is words on purpose
  password="$(first_sshd_value PasswordAuthentication $files)"
  dropin="missing"
  if [ -f "$SSH_DROPIN" ]; then
    dropin="differs"
    [ "$(cat "$SSH_DROPIN")" != "$(ssh_dropin_content "${CHECK_USER}${EXTRA_ALLOWED_USERS:+ $EXTRA_ALLOWED_USERS}")" ] || dropin="in place"
  fi
  print_row "SSH password login" "$password" "set to no"
  print_row "SSH drop-in 00-..." "$dropin" "$([ "$dropin" = "in place" ] && echo nothing || echo write it)"
}

check_keys() {
  local keys count=0
  keys="$(user_home "$CHECK_USER")/.ssh/authorized_keys"
  if [ -r "$keys" ]; then
    count="$(grep -v '^[[:space:]]*#' "$keys" | grep -Ec "$SSH_KEY_PATTERN" || true)"
  fi
  print_row "SSH keys for $CHECK_USER" "$count usable key(s)" "needs at least 1 to apply"
}

check_firewall() {
  local state apps app known
  print_row "firewall" "$(on_off fw_global_on)" "turn on"
  print_row "stealth mode" "$(on_off fw_stealth_on)" "turn on"
  print_row "allow signed apps" "$(on_off fw_downloaded_signed_on)" "turn on"
  apps="$(firewall_apps_found)"
  [ -n "$apps" ] || { print_row "firewall allow list" "no helper programs found" "nothing to add"; return 0; }
  while IFS= read -r app; do
    known=no
    fw_knows_app "$app" && known=yes
    state="listed: $known"
    print_row "allow $(basename "$app")" "$state" "$([ "$known" = yes ] && echo nothing || echo add)"
  done <<EOF
$apps
EOF
}

check_sharing() {
  print_row "Screen Sharing" "$(screen_sharing_state)" "left alone (use --screen-sharing-off)"
  print_row "Remote Management" "$(remote_management_running && echo running || echo off)" "left alone (use --screen-sharing-off)"
  print_row "FileVault" "$(sys_out fdesetup status | head -n 1 || true)" "advice only"
}

run_check() {
  CHECK_USER="${SUDO_USER:-$(id -un)}"
  say "harden-mac check (read-only). Nothing is changed."
  say ""
  print_header
  check_ssh
  check_keys
  check_firewall
  check_sharing
  say ""
  say "To change things: sudo $0 apply --confirm-key-login"
}

# ---- entry point -----------------------------------------------------------------------------

usage() {
  say "Usage: harden-mac.sh [check|apply|confirm|rollback] [--confirm-key-login] [--extra-users \"a,b\"] [--screen-sharing-off]"
}

main() {
  local command=check automatic=0
  while [ $# -gt 0 ]; do
    case "$1" in
      check | apply | confirm | rollback) command="$1" ;;
      --confirm-key-login) KEY_LOGIN_TESTED=1 ;;
      --extra-users) shift; EXTRA_ALLOWED_USERS="${1:?--extra-users needs a value}" ;;
      --screen-sharing-off) SCREEN_SHARING_OFF=1 ;;
      --auto) automatic=1 ;;
      -h | --help) usage; return 0 ;;
      *) usage >&2; return 2 ;;
    esac
    shift
  done
  setup_environment
  is_dry && SOCKETFILTERFW="socketfilterfw"
  [ "$automatic" = 0 ] || log_line "automatic rollback timer fired"
  case "$command" in
    check) run_check ;;
    apply) run_apply ;;
    confirm) require_root; run_confirm ;;
    rollback) require_root; run_rollback ;;
  esac
}

main "$@"
