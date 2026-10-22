"""PUT /v1/workloads/{id}/ssh-keys: the whole list of keys for one VM, applied as a full state.
The keys below are throwaway PUBLIC keys made only for these checks; no private half exists anywhere."""
from contract.tests.support import expect, expect_error, expect_schema

KEY_LINES = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGztuu+WSC2Dy6qKbvBCc28vlAN57G8tHnH19KAWRWHN conformance-1",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEhzPCUXadN4ggXWiblfiGkllLSjLFCa7jnGLciirSec conformance-2",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIy8oqfir0pab+pYtryE26AFjwDkHs8eNb1WQI6k0n9i conformance-3",
]
KEY_BODIES = [line.split()[1] for line in KEY_LINES]
MAX_KEYS = 20
OPTION_PREFIXED_LINE = 'command="x" ' + KEY_LINES[0]
LINE_WITH_NEWLINE = KEY_LINES[0] + "\n" + KEY_LINES[1]
UNKNOWN_WORKLOAD = "nope-nothing-here"


def _path(workload_id):
    return f"/v1/workloads/{workload_id}/ssh-keys"


def _put(ctx, workload_id, body, **kwargs):
    return ctx.client.request("PUT", _path(workload_id), body, **kwargs)


def _no_key_text(reply, label):
    text = reply.raw.decode("utf-8", "replace")
    leaked = [body for body in KEY_BODIES if body in text]
    expect(not leaked, f"{label}: the key text came back in the response")


def _stopped_workload(ctx):
    workload_id, _ = ctx.create_small()
    stopped = ctx.post(f"/v1/workloads/{workload_id}/stop")
    expect(stopped.status == 202, f"stop gave {stopped.status}")
    ctx.wait_for(stopped.body["command_id"])
    return workload_id


def check_ssh_keys_need_the_token(ctx):
    workload_id, _ = ctx.create_small()
    for token in (None, "wrong-token"):
        expect_error(_put(ctx, workload_id, {"keys": KEY_LINES}, token=token), 401, f"ssh-keys with token {token!r}")


def check_ssh_keys_unknown_vm_is_404(ctx):
    reply = _put(ctx, UNKNOWN_WORKLOAD, {"keys": KEY_LINES})
    expect_error(reply, 404, "ssh-keys of an unknown VM")
    _no_key_text(reply, "unknown VM")


def check_ssh_keys_bad_bodies_are_400(ctx):
    workload_id, _ = ctx.create_small()
    too_many = [KEY_LINES[index % len(KEY_LINES)] for index in range(MAX_KEYS + 1)]
    bad_bodies = {
        "an option before the key": {"keys": [OPTION_PREFIXED_LINE]},
        "a newline inside a line": {"keys": [LINE_WITH_NEWLINE]},
        f"{MAX_KEYS + 1} keys": {"keys": too_many},
        "keys that is not an array": {"keys": KEY_LINES[0]},
        "keys that is an object": {"keys": {"a": KEY_LINES[0]}},
        "no keys field": {},
        "an extra field": {"keys": KEY_LINES, "extra": 1},
        "a non-string line": {"keys": [1]},
    }
    for label, body in bad_bodies.items():
        reply = _put(ctx, workload_id, body)
        expect_error(reply, 400, f"ssh-keys with {label}")
        expect(reply.body["error"]["code"] == "invalid_input", f"{label}: wrong code {reply.body}")
        _no_key_text(reply, label)


def check_ssh_keys_bad_body_changes_nothing(ctx):
    workload_id, _ = ctx.create_small()
    first = _put(ctx, workload_id, {"keys": KEY_LINES})
    expect(first.status == 200, f"apply gave {first.status}: {first.body}")
    expect_error(_put(ctx, workload_id, {"keys": [OPTION_PREFIXED_LINE]}), 400, "bad line after a good apply")
    again = _put(ctx, workload_id, {"keys": KEY_LINES})
    expect(again.body == first.body, f"a refused body changed the state: {first.body} then {again.body}")


def check_ssh_keys_stopped_vm_is_409_not_running(ctx):
    reply = _put(ctx, _stopped_workload(ctx), {"keys": KEY_LINES})
    expect_error(reply, 409, "ssh-keys of a stopped VM")
    expect(reply.body["error"]["code"] == "not_running", f"wrong code {reply.body}")
    _no_key_text(reply, "stopped VM")


def check_ssh_keys_apply_counts_the_keys(ctx):
    workload_id, _ = ctx.create_small()
    for count in (len(KEY_LINES), 1, 0):
        reply = _put(ctx, workload_id, {"keys": KEY_LINES[:count]})
        expect(reply.status == 200, f"apply of {count} keys gave {reply.status}: {reply.body}")
        expect_schema("SshKeysApplied", reply.body, f"apply of {count} keys")
        expect(reply.body["applied"] == count, f"applied {reply.body['applied']} for {count} keys")
        _no_key_text(reply, f"apply of {count} keys")


def check_ssh_keys_apply_is_idempotent(ctx):
    workload_id, _ = ctx.create_small()
    answers = [_put(ctx, workload_id, {"keys": KEY_LINES}) for _ in range(2)]
    expect(all(answer.status == 200 for answer in answers), f"apply gave {[a.status for a in answers]}")
    expect(answers[0].body == answers[1].body, f"the same list gave two answers: {answers[0].body} and {answers[1].body}")


def check_ssh_keys_never_appear_in_listings(ctx):
    workload_id, _ = ctx.create_small()
    _put(ctx, workload_id, {"keys": KEY_LINES})
    for path in ("/v1/workloads", "/v1/facts"):
        _no_key_text(ctx.get(path), path)


def _fake_switch(ctx, path, body):
    """True when the target is the Fake Agent (it has the test switches); a real helper answers 404 and is never asked to install anything."""
    return ctx.post(path, body).status == 204


def _stored_keys(ctx, workload_id):
    reply = ctx.get(f"/fake/workloads/{workload_id}/ssh-keys")
    expect(reply.status == 200, f"reading the stored keys gave {reply.status}")
    return reply.body["keys"]


def check_ssh_keys_install_sshd_must_be_a_boolean(ctx):
    workload_id, _ = ctx.create_small()
    for value in ("yes", 1, None, ["true"]):
        reply = _put(ctx, workload_id, {"keys": KEY_LINES, "install_sshd": value})
        expect_error(reply, 400, f"install_sshd {value!r}")
        _no_key_text(reply, f"install_sshd {value!r}")


def check_ssh_keys_install_sshd_false_is_the_plain_call(ctx):
    workload_id, _ = ctx.create_small()
    reply = _put(ctx, workload_id, {"keys": KEY_LINES, "install_sshd": False})
    expect(reply.status == 200, f"install_sshd false gave {reply.status}: {reply.body}")
    expect_schema("SshKeysApplied", reply.body, "install_sshd false")
    expect("installed" not in reply.body, f"the plain call must not say installed: {reply.body}")


def check_ssh_keys_install_sshd_installs_once(ctx):
    workload_id, _ = ctx.create_small()
    if not _fake_switch(ctx, "/fake/ssh-sshd", {"state": "missing"}):
        return
    _fake_switch(ctx, "/fake/ssh-install", {"mode": "works"})
    first = _put(ctx, workload_id, {"keys": KEY_LINES, "install_sshd": True})
    expect(first.status == 200, f"install gave {first.status}: {first.body}")
    expect_schema("SshKeysApplied", first.body, "install")
    expect(first.body == {"applied": len(KEY_LINES), "sshd": "running", "installed": True}, f"wrong answer {first.body}")
    second = _put(ctx, workload_id, {"keys": KEY_LINES, "install_sshd": True})
    expect(second.body == {"applied": len(KEY_LINES), "sshd": "running", "installed": False}, f"the second call installed again: {second.body}")
    _no_key_text(first, "install")
    _no_key_text(second, "second install")


def check_ssh_keys_failed_install_is_502_and_keeps_the_keys(ctx):
    workload_id, _ = ctx.create_small()
    if not _fake_switch(ctx, "/fake/ssh-sshd", {"state": "missing"}):
        return
    _fake_switch(ctx, "/fake/ssh-install", {"mode": "fails"})
    reply = _put(ctx, workload_id, {"keys": KEY_LINES, "install_sshd": True})
    _fake_switch(ctx, "/fake/ssh-install", {"mode": "works"})
    _fake_switch(ctx, "/fake/ssh-sshd", {"state": "running"})
    expect_error(reply, 502, "a failed install")
    expect(reply.body["error"]["code"] == "sshd_install_failed", f"wrong code {reply.body}")
    expect(reply.body["error"]["message"], "the failure has no plain message")
    expect(_stored_keys(ctx, workload_id) == KEY_LINES, "a failed install lost the keys")
    _no_key_text(reply, "failed install")


CHECKS = [
    check_ssh_keys_need_the_token, check_ssh_keys_unknown_vm_is_404, check_ssh_keys_bad_bodies_are_400,
    check_ssh_keys_bad_body_changes_nothing, check_ssh_keys_stopped_vm_is_409_not_running,
    check_ssh_keys_apply_counts_the_keys, check_ssh_keys_apply_is_idempotent, check_ssh_keys_never_appear_in_listings,
    check_ssh_keys_install_sshd_must_be_a_boolean, check_ssh_keys_install_sshd_false_is_the_plain_call,
    check_ssh_keys_install_sshd_installs_once, check_ssh_keys_failed_install_is_502_and_keeps_the_keys,
]
