#!/bin/sh
# Checks the chat screen: strict types (svelte-check and tsc, 0 errors, 0 warnings), its own bun tests pass,
# and bundles/chat/web is exactly what this source builds.
set -e
cd "$(dirname "$0")"
bun install --frozen-lockfile --silent
bun run typecheck
bun test --isolate
fingerprint() { find ../web -type f | sort | xargs shasum | shasum; }
before=$(fingerprint)
bun run build --logLevel silent
if [ "$before" != "$(fingerprint)" ]; then
  echo "FAILED: bundles/chat/web is not what bundles/chat/ui builds. Run bun run build in bundles/chat/ui and keep the result."
  exit 1
fi
echo "OK: chat screen checks passed"
