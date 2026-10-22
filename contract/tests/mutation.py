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
from agent.fake.engine import FakeEngine, SshdInstallFailed
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


def _uninstall_that_changes_nothing():
    def broken(self, body):
        return self._finish(body["command_id"], "bundle_uninstall", body.get("workload_id"), {})

    return broken


def _facts_without_the_helper_version():
    original = FakeEngine._facts

    def broken(self):
        facts = original(self)
        del facts["agent_version"]
        return facts

    return broken


def _facts_with_a_different_helper_version():
    original = FakeEngine._facts

    def broken(self):
        return {**original(self), "agent_version": "someone-else"}

    return broken


def _facts_with_a_build_that_changes():
    original = FakeEngine._facts
    counter = iter(range(10**6))

    def broken(self):
        return {**original(self), "agent_build": f"{next(counter):064x}"}

    return broken


def _facts_with_a_build_that_is_not_hex():
    original = FakeEngine._facts

    def broken(self):
        return {**original(self), "agent_build": "not-a-hash"}

    return broken


def _ssh_keys_that_count_wrong():
    original = FakeEngine.apply_ssh_keys

    def broken(self, workload_id, keys, install_sshd=False):
        answer = original(self, workload_id, keys, install_sshd)
        return {**answer, "applied": answer["applied"] + 1}

    return broken


def _ssh_install_that_loses_the_keys():
    original = FakeEngine.apply_ssh_keys

    def broken(self, workload_id, keys, install_sshd=False):
        try:
            return original(self, workload_id, keys, install_sshd)
        except SshdInstallFailed:
            self._ssh_keys[workload_id] = []
            raise

    return broken


def _ssh_keys_applied_to_a_stopped_vm():
    def broken(self, workload_id, keys, install_sshd=False):
        self._get(workload_id)
        return {"applied": len(keys), "sshd": self.spec.sshd}

    return broken


MUTANTS = [
    ("no input validation", spec, "problems", lambda name, instance: [], "check_create_rejects_bad_names"),
    ("any token accepted", fake_server.hmac, "compare_digest", lambda a, b: True, "check_wrong_token_is_401"),
    ("no disk limit", FakeEngine, "_free_disk", lambda self: 10**9, "check_disk_is_counted_and_returned"),
    ("no RAM limit", FakeEngine, "_free_ram", lambda self: 10**9, "check_ram_counts_only_while_running"),
    ("delete without backup", FakeEngine, "delete", _delete_wrapper(), "check_delete_backs_up_first"),
    ("uninstall changes nothing", FakeEngine, "uninstall_bundle", _uninstall_that_changes_nothing(), "check_machine_uninstall_clears_the_version_in_health"),
    ("facts without the helper version", FakeEngine, "_facts", _facts_without_the_helper_version(), "check_facts"),
    ("facts with a build that is not hex", FakeEngine, "_facts", _facts_with_a_build_that_is_not_hex(), "check_facts"),
    ("facts with a build that changes", FakeEngine, "_facts", _facts_with_a_build_that_changes(), "check_the_build_when_given_is_a_sha256_that_stays_the_same"),
    ("facts name another helper version than health", FakeEngine, "_facts", _facts_with_a_different_helper_version(), "check_facts_say_which_helper_and_engine_run"),
    ("ssh keys without a check of each line", fake_server, "is_valid_key", lambda line: True, "check_ssh_keys_bad_bodies_are_400"),
    ("ssh keys applied to a stopped VM", FakeEngine, "apply_ssh_keys", _ssh_keys_applied_to_a_stopped_vm(), "check_ssh_keys_stopped_vm_is_409_not_running"),
    ("ssh install failure loses the keys", FakeEngine, "apply_ssh_keys", _ssh_install_that_loses_the_keys(), "check_ssh_keys_failed_install_is_502_and_keeps_the_keys"),
    ("ssh keys counted wrong", FakeEngine, "apply_ssh_keys", _ssh_keys_that_count_wrong(), "check_ssh_keys_apply_counts_the_keys"),
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
