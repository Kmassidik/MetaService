#!/bin/sh
# Type-checks the chat screen as JavaScript (jsconfig.json, checkJs) without touching a single file of it, so it stays the same as MAAS's.
# The screen is MAAS's untyped code, so it has errors today: typecheck.baseline holds how many. This fails when there are MORE than that.
# When there are fewer, it says so; lower the number in typecheck.baseline to keep the gain. SVELTE_CHECK is for the tests.
cd "$(dirname "$0")" || exit 1
baseline="$(tr -d ' \n' < typecheck.baseline)"
found="$(${SVELTE_CHECK:-npx svelte-check} --tsconfig ./jsconfig.json --output machine 2>&1 | grep -c ' ERROR ')"
if [ "$found" -gt "$baseline" ]; then
  echo "FAILED: the chat screen has $found type errors, more than the baseline of $baseline. New code must not add type errors."
  exit 1
fi
if [ "$found" -lt "$baseline" ]; then
  echo "OK: $found type errors, below the baseline of $baseline. Lower typecheck.baseline to $found to keep it."
  exit 0
fi
echo "OK: $found type errors, the same as the baseline (the copied MAAS code is untyped)."
