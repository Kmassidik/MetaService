"""SSH keys per VM: a real Root and a fake helper (agent/fake). An operator pastes a user's public key for one VM; the Root checks it strictly, stores it,
and sends the full list to the machine's helper whenever the VM runs (at once when it already does, with a heartbeat when it starts later or the helper was away).
Covers the three panel routes (guards, shapes, refusals, limits), the rules for a key, the helper route of the fake, the audit trail, and that no response ever carries a key body."""
import base64
import hashlib
import sqlite3
import struct
import threading
import time
import urllib.request
from contextlib import contextmanager
from urllib.error import HTTPError

from agent.fake.engine import MachineSpec
from agent.fake.server import make_server
from contract.root_tests.checks_gpu import GpuHelper, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.support import Browser, expect, running
from contract.tests.support import expect_schema

MACHINE = "mini"
HOSTILE_ORIGIN = "http://evil.example"
MAX_KEYS = 20
CHANGES_PER_MINUTE = 30
APPLY_WAIT_SECONDS = 10
ED25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII8umVmLJjfBjjgpC+plmhdOMZ7oWp0XKj9P6E5rrdCA alice@laptop"
ED25519_FINGERPRINT = "SHA256:wcRV5ASFFnhudVdHttpplmBjDQ14KAPHX2yqVl2T2aA"
RSA_1024 = ("ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDKBdOhoDmQjrnz4423vslNHz3P2F0FlONiV+RwBZU6zVT1foLyCwr0N/HlmNLWurf9siK33Sa/BqGBEiWU+XMtpGOyeNFSzPU5s8b7a9Gd"
            "cmE4cQAL8WEL1DrvwWS2j7sQnAtuUs93bbRqDv5D/+1VO0hCudBgnVtzui6FpSh4kw== rsa1024")


def key_body(line):
    return line.split(" ")[1]


def make_key(seed, comment="user@host"):
    """A well-formed ed25519 line made from a seed: a different key for every seed."""
    blob = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + hashlib.sha256(str(seed).encode()).digest()
    return f"ssh-ed25519 {base64.b64encode(blob).decode()}" + (f" {comment}" if comment else "")


def keys_path(vm, machine=MACHINE):
    return f"/api/machines/{machine}/workloads/{vm}/ssh-keys"


@contextmanager
def world(state="running"):
    """A Root with one enrolled machine whose fake helper has one VM in `state`. Yields (root, operator, helper, vm, beat, command_token)."""
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, MachineSpec())
        vm = helper.make("box", kind="vm", gpu_mode="none", state=state)
        tell_the_parent(root, machine_token, helper)
        try:
            yield root, operator, helper, vm, (lambda: tell_the_parent(root, machine_token, helper)), command_token
        finally:
            helper.stop()


def add(operator, vm, line, **kwargs):
    return operator.write("POST", keys_path(vm), {"public_key": line}, **kwargs)


def view(operator, vm):
    reply = operator.request("GET", keys_path(vm))
    expect(reply.status == 200, f"list gave {reply.status}: {reply.raw[:150]!r}")
    expect_schema("SshKeysView", reply.body, "the list")
    return reply.body


def expect_no_key_body(reply, line, label):
    expect(key_body(line).encode() not in reply.raw, f"{label}: the key body is in the response")


def wait_applied(operator, vm, applied=True):
    deadline = time.time() + APPLY_WAIT_SECONDS
    while time.time() < deadline:
        if view(operator, vm)["applied"] is applied:
            return
        time.sleep(0.3)
    raise AssertionError(f"applied never became {applied}: {view(operator, vm)}")


def expect_refused(reply, status, code, label):
    expect(reply.status == status and (reply.body or {}).get("error", {}).get("code") == code, f"{label}: wanted {status} {code}, got {reply.status} {reply.raw[:200]!r}")


# ---- the happy path -----------------------------------------------------------------------------------------------------------------------------------------


def check_ssh_a_key_is_added_applied_listed_and_removed_without_its_body_ever_being_returned():
    with world() as (root, operator, helper, vm, beat, _token):
        expect(view(operator, vm) == {"keys": [], "applied": True, "sshd": "unknown"}, "a VM with no keys")
        reply = add(operator, vm, ED25519)
        expect(reply.status == 201, f"add gave {reply.status}: {reply.raw[:200]!r}")
        expect_schema("SshKeysView", reply.body, "the add answer")
        entry = reply.body["keys"][0]
        expect(len(reply.body["keys"]) == 1 and entry["type"] == "ssh-ed25519" and entry["comment"] == "alice@laptop" and entry["fingerprint"] == ED25519_FINGERPRINT, f"entry: {entry}")
        expect(reply.body["applied"] is True and reply.body["sshd"] == "running", f"applied: {reply.body}")
        expect(helper.engine.ssh_keys_of(vm) == [ED25519], f"the helper got {helper.engine.ssh_keys_of(vm)}")
        expect_no_key_body(reply, ED25519, "add")
        listed = operator.request("GET", keys_path(vm))
        expect(listed.body == reply.body, "the list differs from the add answer")
        expect_no_key_body(listed, ED25519, "list")
        second = add(operator, vm, make_key(1, comment=""))
        expect(second.status == 201 and [k["comment"] for k in second.body["keys"]] == ["alice@laptop", ""], f"second: {second.body}")
        removed = operator.write("DELETE", f"{keys_path(vm)}/{entry['id']}")
        expect(removed.status == 200 and len(removed.body["keys"]) == 1 and removed.body["applied"] is True, f"remove: {removed.status} {removed.body}")
        expect(helper.engine.ssh_keys_of(vm) == [make_key(1, comment="")], "the helper still has the removed key")
        last = operator.write("DELETE", f"{keys_path(vm)}/{removed.body['keys'][0]['id']}")
        expect(last.body["keys"] == [] and helper.engine.ssh_keys_of(vm) == [], "the last key must leave the helper's list empty")


def check_ssh_the_same_key_twice_and_a_twenty_first_key_are_refused_and_nothing_is_lost():
    with world() as (_root, operator, helper, vm, _beat, _token):
        expect(add(operator, vm, ED25519).status == 201, "first add")
        expect_refused(add(operator, vm, ED25519), 409, "duplicate_key", "the same key again")
        expect_refused(add(operator, vm, ED25519.replace("alice@laptop", "other-comment")), 409, "duplicate_key", "the same key with another comment")
        for seed in range(MAX_KEYS - 1):
            expect(add(operator, vm, make_key(seed)).status == 201, f"key {seed}")
        expect_refused(add(operator, vm, make_key(999)), 409, "too_many_keys", "the 21st key")
        expect(len(view(operator, vm)["keys"]) == MAX_KEYS and len(helper.engine.ssh_keys_of(vm)) == MAX_KEYS, "the refused key changed the list")


# ---- what is refused ----------------------------------------------------------------------------------------------------------------------------------------


def check_ssh_a_key_that_is_not_a_plain_key_is_refused_in_plain_words_and_never_reaches_the_helper():
    with world() as (_root, operator, helper, vm, _beat, _token):
        body = key_body(ED25519)
        cases = {
            "command option": (f'command="touch /tmp/x" {ED25519}', "not allowed"),
            "from option": (f'from="10.0.0.1" {ED25519}', "not allowed"),
            "restrict": (f"restrict {ED25519}", "not allowed"),
            "permitopen": (f'permitopen="a:1" {ED25519}', "not allowed"),
            "newline": (f"{ED25519}\n{make_key(1)}", "single line"),
            "newline then option": (f"{ED25519}\ncommand=\"x\" {make_key(1)}", "single line"),
            "carriage return": (f"{ED25519}\r", "single line"),
            "nul": (f"{ED25519}\x00", "single line"),
            "quote in comment": (f'ssh-ed25519 {body} "quoted"', "comment"),
            "space in comment": (f"ssh-ed25519 {body} two words", "comment"),
            "long comment": (f"ssh-ed25519 {body} " + "a" * 65, "comment"),
            "shell in comment": (f"ssh-ed25519 {body} $(id)", "comment"),
            "leading space": (f" {ED25519}", "spaces"),
            "unknown type": (f"ssh-dss {body} x", "not supported"),
            "type does not match": (f"ecdsa-sha2-nistp256 {body} x", "does not match"),
            "garbage key": ("ssh-ed25519 not-base64!! x", "base64"),
            "cut short": (f"ssh-ed25519 {body[:-4]} x", "damaged"),
            "weak rsa": (RSA_1024, "too weak"),
            "too long": (f"ssh-ed25519 {body} x" + " " + "a" * 800, "too long"),
            "empty": ("", None),
            "only a word": ("hello", None),
        }
        for label, (line, words) in cases.items():
            reply = add(operator, vm, line)
            expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"{label}: {reply.status} {reply.raw[:160]!r}")
            expect_schema("Error", reply.body, label)
            expect(words is None or words in reply.body["error"]["message"], f"{label}: message was {reply.body['error']['message']!r}")
        for label, payload in {"no field": {}, "extra field": {"public_key": ED25519, "x": 1}, "a number": {"public_key": 5}, "null": {"public_key": None}}.items():
            expect(operator.write("POST", keys_path(vm), payload).status == 400, f"{label} must be a 400")
        expect(operator.write("POST", keys_path(vm), raw=b"[1]").status == 400, "a list instead of an object")
        expect(view(operator, vm)["keys"] == [] and helper.engine.ssh_keys_of(vm) == [] and helper.engine.ssh_applies == 0, "a refused key was stored or sent")


def check_ssh_unknown_machines_vms_and_keys_are_a_404_on_all_three_routes():
    with world() as (_root, operator, _helper, vm, _beat, _token):
        expect(add(operator, vm, ED25519).status == 201, "add")
        key_id = view(operator, vm)["keys"][0]["id"]
        for label, machine, workload in (("machine", "nope", vm), ("vm", MACHINE, "no-such-vm"), ("bad id", MACHINE, "BAD_ID")):
            path = keys_path(workload, machine)
            expect_refused(operator.request("GET", path), 404, "not_found", f"GET unknown {label}")
            expect_refused(add_to(operator, path), 404, "not_found", f"POST unknown {label}")
            expect_refused(operator.write("DELETE", f"{path}/{key_id}"), 404, "not_found", f"DELETE unknown {label}")
        expect_refused(operator.write("DELETE", f"{keys_path(vm)}/no-such-key"), 404, "not_found", "unknown key")
        expect(len(view(operator, vm)["keys"]) == 1, "a 404 changed the list")


def add_to(operator, path):
    return operator.write("POST", path, {"public_key": ED25519})


# ---- guards and limits --------------------------------------------------------------------------------------------------------------------------------------


def check_ssh_routes_need_a_session_and_writes_need_origin_csrf_and_the_right_host():
    with world() as (root, operator, helper, vm, _beat, _token):
        anonymous = Browser(root, auto_login=False)
        for method in ("GET", "POST", "DELETE"):
            path = keys_path(vm) + ("/key-x" if method == "DELETE" else "")
            expect(anonymous.request(method, path, {"public_key": ED25519} if method == "POST" else None).status == 401, f"{method} without a session")
        expect(operator.request("POST", keys_path(vm), {"public_key": ED25519}).status == 403, "POST without the CSRF token")
        expect(operator.request("DELETE", f"{keys_path(vm)}/key-x").status == 403, "DELETE without the CSRF token")
        expect(add(operator, vm, ED25519, origin=HOSTILE_ORIGIN).status == 403, "POST from a hostile Origin")
        expect(operator.write("DELETE", f"{keys_path(vm)}/key-x", origin=HOSTILE_ORIGIN).status == 403, "DELETE from a hostile Origin")
        expect(operator.request("GET", keys_path(vm), headers={"Host": "evil.example"}).status == 403, "GET with a foreign Host")
        expect(add(operator, vm, ED25519, headers={"Host": "evil.example"}).status == 403, "POST with a foreign Host")
        expect(view(operator, vm)["keys"] == [] and helper.engine.ssh_applies == 0, "a refused request changed something")


def check_ssh_changes_are_rate_limited():
    with world() as (_root, operator, _helper, vm, _beat, _token):
        statuses = [add(operator, vm, "nonsense").status for _ in range(CHANGES_PER_MINUTE + 1)]
        expect(statuses[:CHANGES_PER_MINUTE] == [400] * CHANGES_PER_MINUTE and statuses[-1] == 429, f"statuses: {statuses}")
        expect_refused(operator.write("DELETE", f"{keys_path(vm)}/key-x"), 429, "rate_limited", "a delete past the limit")


# ---- applying -----------------------------------------------------------------------------------------------------------------------------------------------


def check_ssh_a_stopped_vm_stores_the_key_and_gets_it_with_the_heartbeat_that_shows_it_running():
    with world(state="stopped") as (_root, operator, helper, vm, beat, _token):
        reply = add(operator, vm, ED25519)
        expect(reply.status == 201 and reply.body["applied"] is False and len(reply.body["keys"]) == 1, f"stopped add: {reply.status} {reply.body}")
        expect(helper.engine.ssh_keys_of(vm) == [] and helper.engine.ssh_applies == 0, "a stopped VM was sent keys")
        beat()
        time.sleep(1)
        expect(view(operator, vm)["applied"] is False and helper.engine.ssh_applies == 0, "a heartbeat of a stopped VM must not apply")
        helper.engine.set_state("c-up", vm, "start", "running")
        beat()
        wait_applied(operator, vm)
        expect(helper.engine.ssh_keys_of(vm) == [ED25519] and view(operator, vm)["sshd"] == "running", "the key did not arrive after the start")
        expect(operator.write("DELETE", f"{keys_path(vm)}/{view(operator, vm)['keys'][0]['id']}").body["applied"] is True, "removing on a running VM")
        helper.engine.set_state("c-down", vm, "stop", "stopped")
        beat()
        add(operator, vm, make_key(7))
        helper.engine.set_state("c-up2", vm, "start", "running")
        beat()
        wait_applied(operator, vm)
        expect(helper.engine.ssh_keys_of(vm) == [make_key(7)], "the full list is what the helper holds")


def revive(helper, token):
    """A helper that was away comes back on the same address."""
    server = make_server(helper.engine, token, "127.0.0.1", helper.port)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def check_ssh_a_helper_that_is_away_keeps_the_key_as_not_applied_and_catches_up_with_the_next_heartbeat():
    with world() as (_root, operator, helper, vm, beat, token):
        helper.stop()
        reply = add(operator, vm, ED25519)
        expect(reply.status == 201 and reply.body["applied"] is False and len(reply.body["keys"]) == 1, f"away add: {reply.status} {reply.body}")
        server = revive(helper, token)
        try:
            beat()
            wait_applied(operator, vm)
            expect(helper.engine.ssh_keys_of(vm) == [ED25519], "the key did not arrive when the helper came back")
        finally:
            server.shutdown()
            server.server_close()


def check_ssh_what_the_helper_says_about_sshd_is_passed_on_and_remembered():
    with world() as (_root, operator, helper, vm, _beat, _token):
        helper.engine.set_sshd("missing")
        reply = add(operator, vm, ED25519)
        expect(reply.body["applied"] is True and reply.body["sshd"] == "missing", f"missing: {reply.body}")
        helper.engine.set_sshd("installed")
        expect(add(operator, vm, make_key(2)).body["sshd"] == "installed", "installed")
        expect(view(operator, vm)["sshd"] == "installed", "the last report is kept")


# ---- trail, cleanup, the fake helper ------------------------------------------------------------------------------------------------------------------------


def check_ssh_the_audit_trail_names_the_fingerprint_machine_and_vm_but_never_the_key():
    with world() as (_root, operator, _helper, vm, _beat, _token):
        add(operator, vm, ED25519)
        operator.write("DELETE", f"{keys_path(vm)}/{view(operator, vm)['keys'][0]['id']}")
        audit = operator.request("GET", "/api/audit?limit=200")
        entries = {e["action"]: e for e in audit.body["entries"] if e["action"].startswith("ssh_key.")}
        expect(set(entries) == {"ssh_key.add", "ssh_key.remove"}, f"audit actions: {sorted(entries)}")
        for action, entry in entries.items():
            text = str(entry)
            expect(ED25519_FINGERPRINT in text and MACHINE in text and vm in text, f"{action} misses a field: {entry}")
        expect(key_body(ED25519).encode() not in audit.raw, "the key body is in the audit trail")


def check_ssh_deleting_a_vm_removes_its_keys_from_the_parent():
    with world() as (root, operator, helper, vm, beat, _token):
        add(operator, vm, ED25519)
        other = helper.make("other", kind="vm", gpu_mode="none")
        beat()
        add(operator, other, make_key(5))
        expect(operator.write("POST", f"/api/machines/{MACHINE}/workloads/{vm}/delete", {"confirm": True}).status == 202, "delete")
        deadline = time.time() + APPLY_WAIT_SECONDS
        while stored_keys(root, vm) and time.time() < deadline:
            time.sleep(0.3)
        expect(stored_keys(root, vm) == 0, "the deleted VM's keys are still stored")
        expect(stored_keys(root, other) == 1, "another VM's keys must stay")


def stored_keys(root, vm):
    database = sqlite3.connect(f"{root.dir}/root.sqlite3")
    try:
        return database.execute("SELECT COUNT(*) FROM workload_ssh_keys WHERE workload_id = ?", (vm,)).fetchone()[0]
    finally:
        database.close()


def helper_put(helper, token, vm, body, auth=True):
    request = urllib.request.Request(f"http://127.0.0.1:{helper.port}/v1/workloads/{vm}/ssh-keys", data=body, method="PUT",
                                     headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if auth else {})})
    try:
        with urllib.request.urlopen(request, timeout=5) as reply:
            return reply.status, reply.read()
    except HTTPError as error:
        return error.code, error.read()


def check_ssh_the_fake_helper_route_follows_the_helper_contract():
    with world() as (_root, _operator, helper, vm, _beat, token):
        status, raw = helper_put(helper, token, vm, b'{"keys": ["%s"]}' % ED25519.encode())
        expect(status == 200 and b'"applied": 1' in raw, f"apply: {status} {raw!r}")
        status, raw = helper_put(helper, token, vm, b'{"keys": []}')
        expect(status == 200 and b'"applied": 0' in raw and helper.engine.ssh_keys_of(vm) == [], f"empty list: {status} {raw!r}")
        expect(helper_put(helper, token, vm, b'{"keys": ["a\\nb"]}')[0] == 400, "a line break must be a 400")
        expect(helper_put(helper, token, vm, b'{"keys": "x"}')[0] == 400 and helper_put(helper, token, vm, b'{"keys": [], "x": 1}')[0] == 400, "a bad body must be a 400")
        expect(helper_put(helper, token, vm, b'{"keys": []}', auth=False)[0] == 401, "no token")
        expect(helper_put(helper, token, "no-such-vm", b'{"keys": []}')[0] == 404, "unknown VM")
        helper.engine.set_state("c-stop", vm, "stop", "stopped")
        status, raw = helper_put(helper, token, vm, b'{"keys": []}')
        expect(status == 409 and b"not_running" in raw, f"stopped VM: {status} {raw!r}")


CHECKS = [check_ssh_a_key_is_added_applied_listed_and_removed_without_its_body_ever_being_returned,
          check_ssh_the_same_key_twice_and_a_twenty_first_key_are_refused_and_nothing_is_lost,
          check_ssh_a_key_that_is_not_a_plain_key_is_refused_in_plain_words_and_never_reaches_the_helper,
          check_ssh_unknown_machines_vms_and_keys_are_a_404_on_all_three_routes,
          check_ssh_routes_need_a_session_and_writes_need_origin_csrf_and_the_right_host, check_ssh_changes_are_rate_limited,
          check_ssh_a_stopped_vm_stores_the_key_and_gets_it_with_the_heartbeat_that_shows_it_running,
          check_ssh_a_helper_that_is_away_keeps_the_key_as_not_applied_and_catches_up_with_the_next_heartbeat,
          check_ssh_what_the_helper_says_about_sshd_is_passed_on_and_remembered,
          check_ssh_the_audit_trail_names_the_fingerprint_machine_and_vm_but_never_the_key, check_ssh_deleting_a_vm_removes_its_keys_from_the_parent,
          check_ssh_the_fake_helper_route_follows_the_helper_contract]
