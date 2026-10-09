#!/bin/sh
# Starts the Agent for THIS computer, so the computer running the control plane shows up as the first machine.
# The control plane leaves a one-time invite for it (control-plane/arm64/state/local-agent.json); this script uses it the first time, then just runs the Agent.
# Usually started by scripts/run-control-plane.sh. The Agent's own files are in control-plane/arm64/state/local-agent/.
repo=$(cd "$(dirname "$0")/.." && pwd)
state="$repo/control-plane/arm64/state"
agent="$repo/agent/macos"
dir="$state/local-agent"
root_url="${ROOT_AGENT_URL:-http://127.0.0.1:9102}"

[ -x "$agent/.build/debug/metaservice-agent" ] || (cd "$agent" && swift build) || exit 1
mkdir -p "$dir" && chmod 700 "$dir"

if [ ! -f "$dir/agent.token" ]; then
  waited=0
  until [ -f "$state/local-agent.json" ] || [ "$waited" -ge 60 ]; do sleep 1; waited=$((waited + 1)); done
  [ -f "$state/local-agent.json" ] || { echo "no invite from the control plane in $state; start the control plane first" >&2; exit 1; }
  name=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$state/local-agent.json")
  (umask 177; python3 -c "import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))['token'])" "$state/local-agent.json" > "$dir/enroll.token")
  "$agent/.build/debug/metaservice-agent" enroll --root "$root_url" --name "$name" --enrollment-token-file "$dir/enroll.token" --state-dir "$dir" || { rm -f "$dir/enroll.token"; exit 1; }
  rm -f "$dir/enroll.token" "$state/local-agent.json"
fi

exec "$agent/.build/debug/metaservice-agent" run --state-dir "$dir" --engine apple --port 9101 --bind 127.0.0.1 --chat-port 9200 --chat-bind 127.0.0.1 --heartbeat-seconds 5
