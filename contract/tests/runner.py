"""Run the conformance checks against any Agent: python -m contract.tests.runner --url URL --token-file FILE"""
import argparse
import pathlib
import sys

from contract.tests import checks_basic, checks_bundle, checks_workloads
from contract.tests.support import CheckFailed, Client, Context

ALL_CHECKS = checks_basic.CHECKS + checks_workloads.CHECKS + checks_bundle.CHECKS


def run_checks(base_url, token, out=sys.stdout, bundle=None):
    context = Context(Client(base_url, token), bundle)
    failures = 0
    for check in ALL_CHECKS:
        failures += _run_one(check, context, out)
    out.write(f"\n{len(ALL_CHECKS) - failures} passed, {failures} failed, {len(ALL_CHECKS)} checks\n")
    return failures


def _run_one(check, context, out):
    try:
        check(context)
    except Exception as error:  # noqa: BLE001 - any crash of the Agent or the check is a failed check
        out.write(f"FAIL  {check.__name__}: {error!r}\n")
        return 1
    out.write(f"PASS  {check.__name__}\n")
    return 0


def main():
    parser = argparse.ArgumentParser(description="MetaService Agent conformance tests")
    parser.add_argument("--url", required=True)
    parser.add_argument("--token-file", required=True)
    args = parser.parse_args()
    token = pathlib.Path(args.token_file).read_text().strip()
    sys.exit(1 if run_checks(args.url, token) else 0)


if __name__ == "__main__":
    main()
