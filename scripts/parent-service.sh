#!/bin/sh
# Runs the MetaService parent in the background and controls it.
# Usage: parent-service.sh start [parent options] | stop | status | logs
# Where it keeps things: control-plane/arm64/run/ (parent.pid, parent.log, build.log). The tests change these with METASERVICE_* variables (see below).
here="$(cd "$(dirname "$0")/.." && pwd)"
run_dir="${METASERVICE_RUN_DIR:-$here/control-plane/arm64/run}"
pid_file="$run_dir/parent.pid"
log_file="$run_dir/parent.log"
panel_url="${METASERVICE_PANEL_URL:-http://localhost:9100}"
program="${METASERVICE_PARENT_COMMAND:-$here/scripts/start-parent.sh}"
pattern="${METASERVICE_PROCESS_PATTERN:-[.]build/debug/metaservice-root}"
wait_seconds="${METASERVICE_WAIT_SECONDS:-90}"

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
    if [ -z "$(managed_pid)" ]; then break; fi
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
  (umask 077; nohup "$program" "$@" >> "$log_file" 2>&1 & echo $! > "$pid_file")
  wait_until_up
}

stop() {
  stopped=no
  for pid in $(managed_pid) $(pgrep -f "$pattern"); do
    kill "$pid" 2>/dev/null && stopped=yes
    waited=0
    while alive "$pid" && [ "$waited" -lt 15 ]; do sleep 1; waited=$((waited + 1)); done
    alive "$pid" && kill -9 "$pid" 2>/dev/null
  done
  rm -f "$pid_file"
  if [ "$stopped" = yes ]; then echo "      ✓ MetaService is stopped."; else echo "      MetaService is not running."; fi
}

status() {
  pid="$(any_pid)"
  if [ -z "$pid" ]; then echo "      MetaService is not running."; return 0; fi
  echo "      ✓ MetaService is running (pid $pid, up $(ps -o etime= -p "$pid" | tr -d ' ')): $panel_url"
  panel_answers || echo "      ! The program is running but the panel does not answer yet."
}

logs() {
  if [ -f "$log_file" ]; then tail -n 40 "$log_file"; else echo "      No log yet. It appears after MetaService has been started."; fi
}

case "$1" in
  start) shift; start "$@" ;;
  stop) stop ;;
  status) status ;;
  logs) logs ;;
  *) echo "usage: parent-service.sh start|stop|status|logs"; exit 2 ;;
esac
