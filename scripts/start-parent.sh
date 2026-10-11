#!/bin/sh
# Starts the control plane (the Root) for this computer's CPU, from its own folder, where its .env and state/ live. Builds it first if needed.
# Extra options go straight to the program, for example: scripts/start-parent.sh --agent-bind 192.168.100.40
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) folder=arm64 ;;
  *) echo "The control plane for $(uname -s) on $(uname -m) is not built yet. Only control-plane/arm64 (Apple Silicon) exists; see control-plane/x86_64/README.md." >&2; exit 1 ;;
esac
cd "$(dirname "$0")/../control-plane/$folder" || exit 1
python3 ../../scripts/check_env.py .env || exit 1  # the .env first, so a typo in it does not cost a build
[ -x .build/debug/metaservice-root ] || swift build || exit 1
[ -x ../../agent/macos/.build/debug/metaservice-agent ] || (cd ../../agent/macos && swift build) || exit 1
[ -d state/bundles ] || python3 ../../bundles/chat/build.py --out state/bundles >/dev/null
[ -n "$METASERVICE_BUILD_ONLY" ] && exit 0  # the installer builds first, then starts it in the background
exec .build/debug/metaservice-root "$@"
