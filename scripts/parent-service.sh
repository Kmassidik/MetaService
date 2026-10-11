#!/bin/sh
# Runs the MetaService parent in the background and controls it.
# Usage: parent-service.sh start [parent options] | stop | status | logs | login on | login off | login state
# Where it keeps things: control-plane/arm64/run/ (parent.pid, parent.log). The tests change these with METASERVICE_* variables (see below).
here="$(cd "$(dirname "$0")/.." && pwd)"
run_dir="${METASERVICE_RUN_DIR:-$here/control-plane/arm64/run}"
pid_file="$run_dir/parent.pid"
log_file="$run_dir/parent.log"
panel_url="${METASERVICE_PANEL_URL:-http://localhost:9100}"
program="${METASERVICE_PARENT_COMMAND:-$here/scripts/start-parent.sh}"
pattern="${METASERVICE_PROCESS_PATTERN:-[.]build/debug/metaservice-root}"
wait_seconds="${METASERVICE_WAIT_SECONDS:-90}"
label="com.metaservice.parent"
plist="${METASERVICE_LAUNCH_DIR:-$HOME/Library/LaunchAgents}/$label.plist"
domain="gui/$(id -u)"

# launchctl is the Mac's own service manager. With METASERVICE_NO_LAUNCHCTL set it only writes down what it would have run (for tests).
ctl() {
  if [ -n "$METASERVICE_NO_LAUNCHCTL" ]; then echo "launchctl $*" >> "$run_dir/launchctl.calls"; else launchctl "$@"; fi
}

alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
managed_pid() { pid="$(cat "$pid_file" 2>/dev/null)"; alive "$pid" && echo "$pid"; }
any_pid() { managed_pid || pgrep -f "$pattern" | head -1; }
panel_answers() { curl -s -o /dev/null --max-time 2 "$panel_url"; }

# Builds what is missing, quietly: the compiler's output goes to a log, and is shown only if the build fails.
prepare() {
  mkdir -p "$run_dir" && chmod 700 "$run_dir"
  [ -n "$METASERVICE_SKIP_BUILD" ] && return 0
  build_log="$run_dir/build.log"
  echo "      Building MetaService (the first time takes a few minutes). The details are in $build_log"
  (umask 077; METASERVICE_BUILD_ONLY=1 "$program" > "$build_log" 2>&1) && return 0
  echo "      ✗ The build failed. What it said:"
  { grep -E "error|Error|must be|not found|cannot" "$build_log" | tail -n 8; echo "      ... the end of the log:"; tail -n 6 "$build_log"; } | sed 's/^/        /'
  return 1
}

wait_until_up() {
  waited=0
  while [ "$waited" -lt "$wait_seconds" ]; do
    if panel_answers; then echo "      ✓ MetaService is running in the background: $panel_url"; return 0; fi
    if [ ! -f "$plist" ] && [ -z "$(managed_pid)" ]; then break; fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "      ✗ MetaService did not come up. The last lines of its log:"
  tail -n 15 "$log_file" 2>/dev/null | sed 's/^/        /'
  return 1
}

start() {
  existing="$(any_pid)"
  if [ -n "$existing" ]; then echo "      ✓ MetaService is already running (pid $existing): $panel_url"; return 0; fi
  prepare || return 1
  if [ -f "$plist" ]; then
    ctl bootout "$domain/$label" 2>/dev/null
    ctl bootstrap "$domain" "$plist" || return 1
  else
    (umask 077; nohup "$program" "$@" >> "$log_file" 2>&1 & echo $! > "$pid_file")
  fi
  wait_until_up
}

stop() {
  stopped=no
  [ -f "$plist" ] && ctl bootout "$domain/$label" 2>/dev/null && stopped=yes
  for pid in $(managed_pid) $(pgrep -f "$pattern"); do
    kill "$pid" 2>/dev/null && stopped=yes
    waited=0
    while alive "$pid" && [ "$waited" -lt 15 ]; do sleep 1; waited=$((waited + 1)); done
    alive "$pid" && kill -9 "$pid" 2>/dev/null
  done
  rm -f "$pid_file"
  if [ "$stopped" = yes ]; then echo "      ✓ MetaService is stopped."; else echo "      MetaService is not running."; fi
}

login_state() { if [ -f "$plist" ]; then echo on; else echo off; fi; }

status() {
  pid="$(any_pid)"
  if [ -z "$pid" ]; then echo "      MetaService is not running."
  else
    echo "      ✓ MetaService is running (pid $pid, up $(ps -o etime= -p "$pid" | tr -d ' ')): $panel_url"
    panel_answers || echo "      ! The program is running but the panel does not answer yet."
  fi
  echo "      Starts at login: $(login_state)"
}

logs() {
  if [ -f "$log_file" ]; then tail -n 40 "$log_file"; else echo "      No log yet. It appears after MetaService has been started."; fi
}

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

login_on() {
  prepare || return 1
  mkdir -p "$(dirname "$plist")"
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$(xml "$program")</string></array>
  <key>WorkingDirectory</key><string>$(xml "$here")</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$(xml "$log_file")</string>
  <key>StandardErrorPath</key><string>$(xml "$log_file")</string>
</dict>
</plist>
PLIST
  stop >/dev/null
  ctl bootstrap "$domain" "$plist" || return 1
  echo "      ✓ MetaService now starts when you log in, and starts again if it stops."
  wait_until_up
}

login_off() {
  ctl bootout "$domain/$label" 2>/dev/null
  rm -f "$plist"
  echo "      ✓ MetaService no longer starts at login. (If it is running, it was stopped.)"
}

case "$1" in
  start) shift; start "$@" ;;
  stop) stop ;;
  status) status ;;
  logs) logs ;;
  login)
    case "$2" in
      on) login_on ;;
      off) login_off ;;
      state) login_state ;;
      *) echo "usage: parent-service.sh login on|off|state"; exit 2 ;;
    esac ;;
  *) echo "usage: parent-service.sh start|stop|status|logs|login on|off|state"; exit 2 ;;
esac
