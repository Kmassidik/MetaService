#!/bin/sh
# Starts the control plane (the Root) for this computer's CPU, from its own folder, where its .env and state/ live. Builds it first if needed.
# It also starts the Agent for this computer, so this computer is the first machine in the panel. Stop with Ctrl-C: both stop.
# Extra options go straight to the control plane, for example: scripts/run-control-plane.sh --no-local-machine
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) folder=arm64 ;;
  *) echo "The control plane for $(uname -s) on $(uname -m) is not built yet. Only control-plane/arm64 (Apple Silicon) exists; see control-plane/x86_64/README.md." >&2; exit 1 ;;
esac
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo/control-plane/$folder" || exit 1
[ -x .build/debug/metaservice-root ] || swift build || exit 1
[ -d state/bundles ] || python3 ../../bundles/chat/build.py --out state/bundles >/dev/null

case " $* " in
  *" --no-local-machine "*) ;;
  *) mkdir -p state; "$repo/scripts/run-local-agent.sh" > state/local-agent.log 2>&1 & agent=$!; trap 'kill $agent 2>/dev/null' EXIT INT TERM ;;
esac
.build/debug/metaservice-root "$@"
