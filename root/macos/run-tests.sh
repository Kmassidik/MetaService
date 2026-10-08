#!/bin/sh
# Root tests: unit tests, then both Root builds, then the black-box checks against real Root processes.
# Run from anywhere; needs Xcode's Swift and Nix. Stops at the first failure.
set -e
cd "$(dirname "$0")"
swift test 2>&1 | grep -E "Executed|error:|failed" | tail -5
swift build 2>&1 | tail -1
swift build -Xswiftc -DFAKE_AUTH --scratch-path .build-fake 2>&1 | tail -1
cd ../..
nix develop --command python3 -m contract.root_tests.runner | tail -3
