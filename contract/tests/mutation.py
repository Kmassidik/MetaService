"""Proves the conformance suite has teeth: deliberately broken Fake Agents must fail it.

Run: python3 -m contract.tests.mutation
An honest Fake Agent must pass everything, and every mutant must fail at least the named check.
"""
import io
import secrets
import sys
import threading
from contextlib import contextmanager

from agent.fake import server as fake_server
from agent.fake.engine import FakeEngine
from contract import spec
from contract.tests.runner import run_checks


@contextmanager
def _patched(owner, name, replacement):
    original = getattr(owner, name)
    setattr(owner, name, replacement)
    try:
        yield
    finally:
        setattr(owner, name, original)


def _failed_checks():
    token = secrets.token_hex(24)
    server = fake_server.make_server(FakeEngine(), token)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    out = io.StringIO()
    run_checks(f"http://127.0.0.1:{server.server_address[1]}", token, out)
    server.shutdown()
    return {line.split()[1].rstrip(":") for line in out.getvalue().splitlines() if line.startswith("FAIL")}


def _delete_wrapper():
    original = FakeEngine.delete

    def broken(self, command_id, workload_id):
        record = original(self, command_id, workload_id)
        self._commands[command_id]["result"] = {}
        return {**record, "result": {}}

    return broken


MUTANTS = [
    ("no input validation", spec, "problems", lambda name, instance: [], "check_create_rejects_bad_names"),
    ("any token accepted", fake_server.hmac, "compare_digest", lambda a, b: True, "check_wrong_token_is_401"),
    ("no disk limit", FakeEngine, "_free_disk", lambda self: 10**9, "check_disk_is_counted_and_returned"),
    ("no RAM limit", FakeEngine, "_free_ram", lambda self: 10**9, "check_ram_counts_only_while_running"),
    ("delete without backup", FakeEngine, "delete", _delete_wrapper(), "check_delete_backs_up_first"),
]


def main():
    problems = [f"honest Fake Agent failed: {sorted(_failed_checks())}"] if _failed_checks() else []
    for label, owner, name, replacement, must_fail in MUTANTS:
        with _patched(owner, name, replacement):
            caught = _failed_checks()
        print(f"{'caught' if must_fail in caught else 'MISSED'}  mutant: {label}")
        if must_fail not in caught:
            problems.append(f"mutant not caught: {label}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
