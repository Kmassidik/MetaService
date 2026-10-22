"""SSH keys per VM, part two: the helper installs and locks the SSH server, and the panel sees the progress and the command to log in with.
A real Root and a fake helper (agent/fake). The apply runs in the background, so these checks watch `sshd_state` go installing -> idle (or failed),
the retry route, the machine setting `ssh_jump` and the `connect` block. No key text may appear in any answer."""
import sqlite3
import time

from contract.root_tests.checks_ssh_keys import ED25519, MACHINE, add, expect_no_key_body, expect_refused, keys_path, make_key, view, wait_applied, world
from contract.root_tests.support import expect

STATE_WAIT_SECONDS = 15
INSTALL_DELAY_SECONDS = 2
OFFICE_USER, OFFICE_HOST, OFFICE_PORT = "kurnia", "192.168.1.20", 2222
VM_ADDRESS = "192.168.64.5"
SETTING_JUMP = "you@203.0.113.7"
INSTALL_FAILED_MESSAGE = "The VM could not download the SSH server. Check that the VM has internet access."
STALE_SECONDS = 600
HOSTILE_JUMPS = ["you", "you@", "you@host; reboot", "you@host:99999", "$(id)@host", "you@ho st", "a" * 130 + "@host"]


def retry_path(vm):
    return keys_path(vm) + "/retry"


def wait_state(operator, vm, state):
    deadline = time.time() + STATE_WAIT_SECONDS
    while time.time() < deadline:
        current = view(operator, vm)
        if current["sshd_state"] == state:
            return current
        time.sleep(0.2)
    raise AssertionError(f"sshd_state never became {state}: {view(operator, vm)}")


def set_jump(operator, value):
    return operator.write("PATCH", f"/api/machines/{MACHINE}/settings", {"ssh_jump": value})


def give_address(helper, beat, vm, address):
    helper.engine._get(vm)["address"] = address
    beat()


def database_of(root):
    return sqlite3.connect(f"{root.dir}/root.sqlite3")


def add_office_row(root):
    database = database_of(root)
    try:
        database.execute("INSERT INTO remote_machines (machine, host, ssh_port, ssh_user, fingerprint, level, box, ssh_dir, agent_port, engine, created_at) "
                         "VALUES (?, ?, ?, ?, 'fp', 'user', '/tmp/box', '/tmp/ssh', 8080, 'incus', 0)", (MACHINE, OFFICE_HOST, OFFICE_PORT, OFFICE_USER))
        database.commit()
    finally:
        database.close()


def check_ssh_an_install_shows_installing_then_idle_and_the_helper_ends_with_a_running_server():
    with world() as (_root, operator, helper, vm, _beat, _token):
        helper.engine.set_sshd("missing")
        helper.engine.set_ssh_install("works", INSTALL_DELAY_SECONDS)
        reply = add(operator, vm, ED25519)
        expect(reply.status == 201 and reply.body["sshd_state"] == "installing" and reply.body["sshd_message"] is None, f"the add must answer at once with installing: {reply.body}")
        expect(view(operator, vm)["sshd_state"] == "installing", "still installing while the helper works")
        done = wait_state(operator, vm, "idle")
        expect(done["applied"] is True and done["sshd"] == "running" and done["sshd_message"] is None, f"after the install: {done}")
        expect(helper.engine.ssh_keys_of(vm) == [ED25519], "the key must be in the VM")
        expect_no_key_body(reply, ED25519, "add")


def check_ssh_a_failed_install_keeps_the_keys_shows_the_reason_and_waits_a_minute_before_the_heartbeat_retries():
    with world() as (_root, operator, helper, vm, beat, _token):
        helper.engine.set_sshd("missing")
        helper.engine.set_ssh_install("fails", 0)
        add(operator, vm, ED25519)
        failed = wait_state(operator, vm, "failed")
        expect(failed["sshd_message"] == INSTALL_FAILED_MESSAGE and failed["applied"] is False, f"failed view: {failed}")
        expect(helper.engine.ssh_keys_of(vm) == [ED25519], "the keys must be written even when the install failed")
        applies = helper.engine.ssh_applies
        beat()
        time.sleep(1)
        expect(helper.engine.ssh_applies == applies and view(operator, vm)["sshd_state"] == "failed", "the heartbeat must wait a minute after a failure")
        expect_no_key_body(operator.request("GET", keys_path(vm)), ED25519, "failed view")


def check_ssh_retry_applies_now_and_ends_idle_once_the_helper_can_install():
    with world() as (_root, operator, helper, vm, _beat, _token):
        helper.engine.set_sshd("missing")
        helper.engine.set_ssh_install("fails", 0)
        add(operator, vm, ED25519)
        wait_state(operator, vm, "failed")
        helper.engine.set_ssh_install("works", INSTALL_DELAY_SECONDS)
        reply = operator.write("POST", retry_path(vm))
        expect(reply.status == 200 and reply.body["sshd_state"] == "installing", f"retry: {reply.status} {reply.raw[:200]!r}")
        done = wait_state(operator, vm, "idle")
        expect(done["applied"] is True and done["sshd"] == "running", f"after the retry: {done}")


def check_ssh_retry_is_guarded_like_every_operator_write_and_needs_a_running_vm():
    with world() as (_root, operator, helper, vm, beat, _token):
        expect_refused(operator.write("POST", retry_path("nope")), 404, "not_found", "unknown VM")
        expect(operator.request("POST", retry_path(vm), origin=None).status in (401, 403), "no Origin and CSRF")
        helper.engine.set_state("c-down", vm, "stop", "stopped")
        beat()
        expect_refused(operator.write("POST", retry_path(vm)), 409, "not_running", "retry on a stopped VM")


def check_ssh_an_install_that_died_is_read_as_failed_and_the_heartbeat_takes_it_over():
    with world() as (root, operator, helper, vm, beat, _token):
        add(operator, vm, ED25519)
        wait_state(operator, vm, "idle")
        database = database_of(root)
        try:
            database.execute("UPDATE workload_ssh_state SET sshd_state = 'installing', sshd_since = ?, applied = 0 WHERE workload_id = ?", (int(time.time()) - STALE_SECONDS, vm))
            database.commit()
        finally:
            database.close()
        stale = view(operator, vm)
        expect(stale["sshd_state"] == "failed" and stale["sshd_message"], f"a dead install must not stay installing: {stale}")
        beat()
        wait_state(operator, vm, "idle")
        wait_applied(operator, vm)


def check_ssh_the_setting_is_validated_echoed_and_changes_the_login_command():
    with world() as (_root, operator, helper, vm, beat, _token):
        give_address(helper, beat, vm, VM_ADDRESS)
        add(operator, vm, ED25519)
        wait_applied(operator, vm)
        expect(view(operator, vm)["connect"] == {"jump": None, "jump_is_default": False, "vm_address": VM_ADDRESS, "command": None}, f"no jump yet: {view(operator, vm)['connect']}")
        for hostile in HOSTILE_JUMPS:
            expect(set_jump(operator, hostile).status == 400, f"{hostile[:30]!r} must be refused")
        saved = set_jump(operator, SETTING_JUMP)
        expect(saved.status == 200 and saved.body["settings"]["ssh_jump"] == SETTING_JUMP, f"saved: {saved.status} {saved.raw[:200]!r}")
        connect = view(operator, vm)["connect"]
        expect(connect == {"jump": SETTING_JUMP, "jump_is_default": False, "vm_address": VM_ADDRESS, "command": f"ssh -J {SETTING_JUMP} root@{VM_ADDRESS}"}, f"connect: {connect}")
        expect(set_jump(operator, None).status == 200 and view(operator, vm)["connect"]["command"] is None, "clearing the setting removes the command")


def check_ssh_without_a_setting_the_machines_office_address_is_the_default_jump():
    with world() as (root, operator, helper, vm, beat, _token):
        give_address(helper, beat, vm, VM_ADDRESS)
        add_office_row(root)
        connect = view(operator, vm)["connect"]
        expected = f"{OFFICE_USER}@{OFFICE_HOST}:{OFFICE_PORT}"
        expect(connect == {"jump": expected, "jump_is_default": True, "vm_address": VM_ADDRESS, "command": f"ssh -J {expected} root@{VM_ADDRESS}"}, f"default jump: {connect}")
        set_jump(operator, SETTING_JUMP)
        expect(view(operator, vm)["connect"]["jump_is_default"] is False and view(operator, vm)["connect"]["jump"] == SETTING_JUMP, "the setting must win")


def check_ssh_a_vm_without_an_address_has_no_login_command():
    with world() as (_root, operator, _helper, vm, _beat, _token):
        set_jump(operator, SETTING_JUMP)
        connect = view(operator, vm)["connect"]
        expect(connect["vm_address"] is None and connect["command"] is None and connect["jump"] == SETTING_JUMP, f"no VM address: {connect}")


def check_ssh_a_hostile_vm_address_never_reaches_the_login_command():
    with world() as (_root, operator, helper, vm, beat, _token):
        set_jump(operator, SETTING_JUMP)
        for hostile in ("10.0.0.7; reboot", "$(id)", "a b", "-oProxyCommand=x"):
            give_address(helper, beat, vm, hostile)
            connect = view(operator, vm)["connect"]
            expect(connect["vm_address"] is None and connect["command"] is None, f"{hostile!r} got into the view: {connect}")
        expect(make_key(1) not in str(view(operator, vm)), "no key in the view")


CHECKS = [check_ssh_an_install_shows_installing_then_idle_and_the_helper_ends_with_a_running_server,
          check_ssh_a_failed_install_keeps_the_keys_shows_the_reason_and_waits_a_minute_before_the_heartbeat_retries,
          check_ssh_retry_applies_now_and_ends_idle_once_the_helper_can_install,
          check_ssh_retry_is_guarded_like_every_operator_write_and_needs_a_running_vm,
          check_ssh_an_install_that_died_is_read_as_failed_and_the_heartbeat_takes_it_over,
          check_ssh_the_setting_is_validated_echoed_and_changes_the_login_command,
          check_ssh_without_a_setting_the_machines_office_address_is_the_default_jump,
          check_ssh_a_vm_without_an_address_has_no_login_command,
          check_ssh_a_hostile_vm_address_never_reaches_the_login_command]
