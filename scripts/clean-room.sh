#!/bin/sh
# Builds and tests the last commit in a brand-new folder, so nothing left in your working folder can hide a problem.
# Only committed files are used. Needs the same things as test-all.sh. Usage: scripts/clean-room.sh [--keep]
set -e
repo="$(cd "$(dirname "$0")/.." && pwd)"
room="$(mktemp -d "${TMPDIR:-/tmp}/metaservice-clean-room.XXXXXX")"
keep=no
[ "$1" = "--keep" ] && keep=yes
finish() { [ "$keep" = "yes" ] && echo "kept: $room" || rm -rf "$room"; }
trap finish EXIT

echo "== clean room: $room"
git clone --quiet --local "$repo" "$room/MetaService"
echo "== commit: $(git -C "$room/MetaService" log -1 --format='%h %s')"
cd "$room/MetaService"

echo "== install the panel's packages from the lock file"
nix develop --command bash -c 'cd frontend && npm ci --silent --no-audit --no-fund'

scripts/test-all.sh
