#!/bin/sh
# Runs every test in the repo. Needs Xcode's Swift, Nix, and Google Chrome (for the browser test). Stops at the first failure.
set -e
cd "$(dirname "$0")"
# Runs a command, shows its last lines, and stops the whole script if it printed a failure.
steady() { out="$("$@" 2>&1)" || { echo "$out" | tail -8; echo "FAILED: $*"; exit 1; }; echo "$out" | tail -1; case "$out" in *" 0 failed"*|*OK*) ;; *) echo "$out" | tail -8; echo "FAILED: $*"; exit 1;; esac; }
swift_summary() { grep -E "Executed [0-9]+ tests|error:" | tail -1; }

echo "== shared rules";   (cd shared/metaservice-shared && swift test 2>&1 | swift_summary)
echo "== root";           (cd root/macos && swift test 2>&1 | swift_summary; swift build 2>&1 | tail -1; swift build -Xswiftc -DFAKE_AUTH --scratch-path .build-fake 2>&1 | tail -1)
echo "== macOS agent";    (cd agent/macos && swift test 2>&1 | swift_summary; swift build 2>&1 | tail -1)
echo "== linux agent (Rust)"
(cd agent/linux && nix develop --command bash -c 'cargo test 2>&1 | grep -E "test result" ; cargo clippy --all-targets -- -D warnings 2>&1 | tail -1')
echo "== contract (fake agent, then the suite's own mutants)"
steady nix develop --command python3 -m contract.tests.run_fake
nix develop --command python3 -m contract.tests.mutation | tail -5
echo "== contract against the macOS agent (simulated engine, then the Apple engine on a fake container program)"
steady nix develop --command python3 -m contract.tests.run_macos_agent
steady nix develop --command python3 -m contract.tests.run_macos_agent --apple
steady nix develop --command python3 -m contract.tests.run_linux_agent
steady nix develop --command python3 -m contract.tests.run_linux_agent --incus
echo "== macOS agent checks"
steady nix develop --command python3 -m contract.agent_tests.runner
steady nix develop --command python3 -m contract.agent_tests.runner --linux
echo "== root checks"
steady nix develop --command python3 -m contract.root_tests.runner
echo "== chat bundle"
steady nix develop --command python3 -m unittest discover -s bundles/chat/tests
echo "== root and agents together"
steady nix develop --command python3 -m contract.system_tests.runner
echo "== panel (UI)"
nix develop --command bash -c 'cd ui && npm run check --silent && npm test --silent 2>&1 | grep -E "^ℹ (pass|fail)" && npm run build --silent && node e2e/panel.e2e.mjs | tail -1'
echo "all tests passed"
