"""Run the macOS Agent checks: python -m contract.agent_tests.runner  (needs the Agent build and the fake-auth Root build)"""
import os
import sys
import time

LINUX = "--linux" in sys.argv
if LINUX:
    os.environ["MS_AGENT_BINARY"] = os.path.join(os.path.dirname(__file__), "..", "..", "agent", "linux", "target", "debug", "metaservice-agent")

from contract.agent_tests import checks_agent, checks_apple, checks_incus  # noqa: E402

ALL_CHECKS = checks_agent.CHECKS + (checks_incus.CHECKS if LINUX else checks_apple.CHECKS)


def main():
    failures = 0
    for check in ALL_CHECKS:
        started = time.time()
        try:
            check()
        except Exception as error:  # noqa: BLE001 - any crash is a failed check
            failures += 1
            print(f"FAIL  {check.__name__}: {error!r}")
            continue
        print(f"PASS  {check.__name__} ({time.time() - started:.1f}s)")
    print(f"\n{len(ALL_CHECKS) - failures} passed, {failures} failed, {len(ALL_CHECKS)} checks")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
