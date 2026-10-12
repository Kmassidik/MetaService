#!/bin/sh
# Checks the chat screen: no lint errors, no more type errors than before, its own tests pass, and bundles/chat/web is exactly what this source builds.
set -e
cd "$(dirname "$0")"
npm ci --silent --no-audit --no-fund
npx eslint src --quiet
sh typecheck.sh
npx vitest run
fingerprint() { find ../web -type f | sort | xargs shasum | shasum; }
before=$(fingerprint)
npm run build --silent
if [ "$before" != "$(fingerprint)" ]; then
  echo "FAILED: bundles/chat/web is not what bundles/chat/ui builds. Run npm run build in bundles/chat/ui and keep the result."
  exit 1
fi
echo "OK: chat screen checks passed"
