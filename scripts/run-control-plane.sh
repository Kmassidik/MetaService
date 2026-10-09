#!/bin/sh
# Starts the control plane (the Root) from its own folder, where its .env and its state/ live. Builds it first if needed.
# Extra options go straight to the program, for example: scripts/run-control-plane.sh --agent-bind 192.168.100.40
cd "$(dirname "$0")/../control-plane" || exit 1
[ -x .build/debug/metaservice-root ] || swift build || exit 1
[ -d state/bundles ] || python3 ../bundles/chat/build.py --out state/bundles >/dev/null
exec .build/debug/metaservice-root "$@"
