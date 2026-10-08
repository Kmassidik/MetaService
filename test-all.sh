#!/bin/sh
# Runs every test in the repo. Needs Xcode's Swift, Nix, and Google Chrome (for the browser test). Stops at the first failure.
set -e
cd "$(dirname "$0")"
swift_summary() { grep -E "Executed [0-9]+ tests|error:" | tail -1; }

echo "== shared rules";   (cd shared/metaservice-shared && swift test 2>&1 | swift_summary)
echo "== root";           (cd root/macos && swift test 2>&1 | swift_summary; swift build 2>&1 | tail -1; swift build -Xswiftc -DFAKE_AUTH --scratch-path .build-fake 2>&1 | tail -1)
echo "== macOS agent";    (cd agent/macos && swift test 2>&1 | swift_summary; swift build 2>&1 | tail -1)
echo "== contract (fake agent, then the suite's own mutants)"
nix develop --command python3 -m contract.tests.run_fake | tail -1
nix develop --command python3 -m contract.tests.mutation | tail -5
echo "== contract against the macOS agent"
nix develop --command python3 -m contract.tests.run_macos_agent | tail -1
echo "== macOS agent checks"
nix develop --command python3 -m contract.agent_tests.runner | tail -1
echo "== root checks"
nix develop --command python3 -m contract.root_tests.runner | tail -1
echo "== panel (UI)"
nix develop --command bash -c 'cd ui && npm run check --silent && npm test --silent 2>&1 | grep -E "^ℹ (pass|fail)" && npm run build --silent && node e2e/panel.e2e.mjs | tail -1'
echo "all tests passed"
