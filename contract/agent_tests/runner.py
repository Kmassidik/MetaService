"""Run the macOS Agent checks: python -m contract.agent_tests.runner [--linux | --fake]  (needs the Agent build and the fake-auth Root build)"""
import os
import sys
import time

LINUX = "--linux" in sys.argv
FAKE = "--fake" in sys.argv
if LINUX:
    os.environ["MS_AGENT_BINARY"] = os.path.join(os.path.dirname(__file__), "..", "..", "agent", "linux", "target", "debug", "metaservice-agent")

from contract.agent_tests import checks_agent, checks_apple, checks_apple_start, checks_images, checks_incus, checks_monitor, checks_sandbox, checks_storage_restart, checks_terminal  # noqa: E402

# The Linux helper reads /proc, which this computer may not have (a Mac): then its monitor checks cannot run here.
MONITOR_CHECKS = checks_monitor.CHECKS if (not LINUX or os.path.exists("/proc/stat")) else []
# Only a Linux helper has a sandbox engine (the simulated one for now); the macOS helper has no sandbox routes at all, so it is not asked to have them.
SANDBOX_CHECKS = checks_sandbox.CHECKS if (LINUX or FAKE) else []

# `--fake` runs only the console checks, against the Fake Agent (agent/fake) instead of a built helper.
if FAKE:
    os.environ["MS_HELPER"] = "fake"
    ALL_CHECKS = checks_terminal.CHECKS + checks_monitor.CHECKS + checks_monitor.FAKE_CHECKS + checks_images.CHECKS + checks_images.FAKE_CHECKS + SANDBOX_CHECKS
else:
    ALL_CHECKS = checks_agent.CHECKS + (checks_incus.CHECKS if LINUX else checks_apple.CHECKS + checks_apple_start.CHECKS) + checks_terminal.CHECKS + MONITOR_CHECKS + checks_images.CHECKS + SANDBOX_CHECKS + checks_storage_restart.CHECKS


def main():
    failures = 0
    words = [word for word in sys.argv[1:] if not word.startswith("--")]  # optional: only the checks whose name holds one of these words
    checks = [check for check in ALL_CHECKS if not words or any(word in check.__name__ for word in words)]
    for check in checks:
        started = time.time()
        try:
            check()
        except Exception as error:  # noqa: BLE001 - any crash is a failed check
            failures += 1
            print(f"FAIL  {check.__name__}: {error!r}")
            continue
        print(f"PASS  {check.__name__} ({time.time() - started:.1f}s)")
    print(f"\n{len(checks) - failures} passed, {failures} failed, {len(checks)} checks")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
