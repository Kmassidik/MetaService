#!/bin/sh
# Starts MetaService again after a reboot with nobody logged in: ./install.sh autostart on|off|status
# `on` installs two system LaunchDaemons that run as the person who typed the command (plist key UserName):
#   io.metaservice.parent     the parent (control-plane/arm64/.build/debug/metaservice-root), kept running
#   io.metaservice.connector  the Cloudflare connector, only when remote access is set up (state/cloudflared.token) and cloudflared is installed
# It never asks for or stores a password: it uses `sudo -n`, and when that is not possible it prints the exact commands to run yourself.
# The tests change the places with METASERVICE_DAEMONS_DIR, METASERVICE_AGENTS_DIR, METASERVICE_LAUNCHCTL, METASERVICE_ROOT and METASERVICE_PANEL_URL.
here="$(cd "$(dirname "$0")/.." && pwd)"
root="${METASERVICE_ROOT:-$here}"
daemons_dir="${METASERVICE_DAEMONS_DIR:-/Library/LaunchDaemons}"
agents_dir="${METASERVICE_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
launchctl="${METASERVICE_LAUNCHCTL:-launchctl}"
panel_url="${METASERVICE_PANEL_URL:-http://127.0.0.1:9100}"
wait_seconds="${METASERVICE_WAIT_SECONDS:-90}"
parent_label="io.metaservice.parent"
connector_label="io.metaservice.connector"
agent_label="io.metaservice.cloudflared"  # the user job that scripts/remote_access made before; the connector daemon replaces it
control_plane="$root/control-plane/arm64"
binary="$control_plane/.build/debug/metaservice-root"
staging_dir="$control_plane/run/autostart"
priv=""
owner_flags=""  # root:wheel is what launchd requires of a daemon plist; only set when the folder is root's
mode="run"

plist_path() { echo "$daemons_dir/$1.plist"; }
staged_path() { echo "$staging_dir/$1.plist"; }
panel_answers() { curl -s -o /dev/null --max-time 2 "$panel_url"; }
is_loaded() { "$launchctl" print "system/$1" >/dev/null 2>&1; }
job_pid() { "$launchctl" print "system/$1" 2>/dev/null | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\)$/\1/p' | head -1; }

# Runs one administrator step, or (when sudo is not available) only prints it, so the person can run it.
priv_step() {
  if [ "$mode" = print ]; then echo "      sudo $*"; return 0; fi
  $priv "$@"
}

# Decides how to do the administrator steps. Sets priv and mode. Returns 1 when they have to be done by hand.
choose_privilege() {
  if [ -w "$daemons_dir" ]; then priv=""; return 0; fi
  owner_flags="-o root -g wheel"
  if sudo -n true 2>/dev/null; then priv="sudo -n"; return 0; fi
  mode=print
  return 1
}

explain_by_hand() {
  echo "      ✗ $daemons_dir belongs to root, and sudo wants a password here. Nothing was changed."
  echo "        Either run \`sudo -v\` and then this command again, or run these commands yourself:"
}

staged_labels() {
  for label in "$parent_label" "$connector_label"; do
    [ -f "$(staged_path "$label")" ] && echo "$label"
  done
}

stage_plists() {
  mkdir -p "$staging_dir" && chmod 700 "$staging_dir" || return 1
  rm -f "$(staged_path "$parent_label")" "$(staged_path "$connector_label")"
  written="$(python3 "$here/scripts/autostart_plists.py" --root "$root" --out "$staging_dir" --user "$(id -un)" --home "$HOME")" || return 1
  echo "$written" | sed 's/^/      /'
}

# Log files are made now, by the person, so the daemon (which runs as the same person) can always write them.
prepare_logs() {
  mkdir -p "$control_plane/run" "$control_plane/state" || return 1
  : >> "$control_plane/run/parent.log" && : >> "$control_plane/state/cloudflared.log"
}

# bootout first, so a daemon that is already loaded is replaced; "not loaded" is the normal case and is not an error.
daemon_replace() {
  priv_step "$launchctl" bootout "system/$1" 2>/dev/null
  priv_step install -m 644 $owner_flags "$(staged_path "$1")" "$(plist_path "$1")"
  priv_step "$launchctl" bootstrap system "$(plist_path "$1")"
}

daemon_remove() {
  priv_step "$launchctl" bootout "system/$1" 2>/dev/null
  priv_step rm -f "$(plist_path "$1")"
}

place_and_load() {
  for label in $(staged_labels); do
    daemon_replace "$label" || return 1
  done
}

stop_manual_parent() {
  echo "      Stopping the parent that was started by hand"
  sh "$here/scripts/parent-service.sh" stop
}

# The user job from `remote up` would run next to the daemon after a login, so it is unloaded and its file removed. `remote up` is safe to run again later.
retire_user_connector() {
  echo "      Handing the connector over from the user job ($agent_label) to the daemon"
  for domain in "gui/$(id -u)" "user/$(id -u)"; do
    "$launchctl" bootout "$domain/$agent_label" >/dev/null 2>&1  # not loaded in one of the two domains is normal
  done
  rm -f "$agents_dir/$agent_label.plist"
}

wait_for_panel() {
  waited=0
  while [ "$waited" -lt "$wait_seconds" ]; do
    panel_answers && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

refuse_unless_ready() {
  if [ "$(id -u)" = 0 ]; then echo "      ✗ Run this as your normal user, not as root: the daemons run as the person who types the command."; return 1; fi
  if [ ! -x "$binary" ]; then echo "      ✗ MetaService is not built yet ($binary is missing). Run ./install.sh install first."; return 1; fi
}

report_started() {
  if wait_for_panel; then echo "      ✓ Autostart is on. MetaService starts at boot, with nobody logged in, and comes back if it stops: $panel_url"; return 0; fi
  echo "      ✗ The daemons are installed but the panel does not answer on $panel_url yet. Look at $control_plane/run/parent.log"
  return 1
}

autostart_on() {
  refuse_unless_ready || return 1
  prepare_logs && stage_plists || return 1
  if ! choose_privilege; then
    explain_by_hand
    echo "      sh $here/scripts/parent-service.sh stop"
    place_and_load
    return 1
  fi
  stop_manual_parent
  [ -f "$(staged_path "$connector_label")" ] && retire_user_connector
  place_and_load || { echo "      ✗ launchd would not load a daemon. Nothing else was changed."; return 1; }
  report_started
}

autostart_off() {
  if ! choose_privilege; then
    explain_by_hand
    for label in "$parent_label" "$connector_label"; do daemon_remove "$label"; done
    return 1
  fi
  for label in "$parent_label" "$connector_label"; do daemon_remove "$label"; done
  echo "      ✓ Autostart is off. The daemons are removed, so MetaService is now stopped and will not start at boot."
  echo "        Start it by hand with ./install.sh install. If remote access was set up, ./install.sh remote up puts its connector back."
}

describe_daemon() {
  label="$1"
  if [ ! -f "$(plist_path "$label")" ]; then echo "      $label: not installed"; return 0; fi
  if ! is_loaded "$label"; then echo "      $label: installed, NOT loaded"; return 0; fi
  pid="$(job_pid "$label")"
  if [ -n "$pid" ]; then echo "      $label: installed, loaded, running (pid $pid)"; else echo "      $label: installed, loaded, not running"; fi
}

autostart_status() {
  describe_daemon "$parent_label"
  describe_daemon "$connector_label"
  if panel_answers; then echo "      The panel answers: $panel_url"; else echo "      The panel does not answer on $panel_url."; fi
}

case "$1" in
  on) autostart_on ;;
  off) autostart_off ;;
  status) autostart_status ;;
  installed) [ -f "$(plist_path "$parent_label")" ] ;;
  *) echo "usage: ./install.sh autostart on|off|status"; exit 2 ;;
esac
