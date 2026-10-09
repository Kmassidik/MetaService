"""Run the Root black-box checks: python -m contract.root_tests.runner  (needs both Root builds, see root/macos/run-tests.sh)"""
import sys
import time

from contract.root_tests import checks_abuse, checks_agents, checks_auth, checks_brain, checks_public, checks_scan

ALL_CHECKS = checks_public.CHECKS + checks_auth.CHECKS + checks_agents.CHECKS + checks_abuse.CHECKS + checks_brain.CHECKS + checks_scan.CHECKS


def main():
    failures = 0
    for check in ALL_CHECKS:
        started = time.time()
        try:
            check()
        except checks_scan.Skip as why:
            print(f"SKIP  {check.__name__}: {why}")
            continue
        except Exception as error:  # noqa: BLE001 - any crash is a failed check
            failures += 1
            print(f"FAIL  {check.__name__}: {error!r}")
            continue
        print(f"PASS  {check.__name__} ({time.time() - started:.1f}s)")
    print(f"\n{len(ALL_CHECKS) - failures} passed, {failures} failed, {len(ALL_CHECKS)} checks")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
