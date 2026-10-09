"""Run the Root + Agent end-to-end checks: python -m contract.system_tests.runner"""
import sys
import time

from contract.system_tests import checks_brain, checks_bundles, checks_workloads

ALL_CHECKS = checks_workloads.CHECKS + checks_bundles.CHECKS + checks_brain.CHECKS


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
