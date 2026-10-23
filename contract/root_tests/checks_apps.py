"""Apps on top of a VM (OpenClaw, Hermes): a real Root and a fake helper (agent/fake). A create with `bundle: openclaw` makes the VM from the stock image and the parent installs the app
afterwards, in the background, through the helper's PUT /v1/workloads/{id}/app. These checks watch the app go installing -> ready (or failed), the retry route and its wait rule,
the machine list, the catalog readiness mapping, an older helper, the guards and limits, and that the audit trail never carries installer output."""
import sqlite3
import time
from contextlib import contextmanager

from agent.fake.engine import MachineSpec
from contract.root_tests.checks_gpu import GpuHelper, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.support import Browser, expect, running
from contract.tests.support import expect_schema

MACHINE = "mini"
STATE_WAIT_SECONDS = 20
COMMAND_WAIT_SECONDS = 20
INSTALL_DELAY_SECONDS = 2
RETRIES_PER_MINUTE = 30
HOSTILE_ORIGIN = "http://evil.example"
UPDATE_HELPER = "Update the helper on this machine first"
OLD_HELPER_FAILURE = "This machine's helper is too old for apps. Press Update helper in its Environment tab."
FAKE_FAILURE = "The installer could not download the app. Check that the VM has internet access."
FAKE_LOG_LINE = "curl: (6) Could not resolve host"
VM = {"kind": "vm", "cpu": 1, "ram_mb": 1024, "disk_gb": 5}


def app_path(vm, machine=MACHINE):
    return f"/api/machines/{machine}/workloads/{vm}/app"


@contextmanager
def world(machine_spec=None):
    """A Root with one enrolled machine and a fake helper that has one running VM called box. Yields (root, operator, helper, vm, beat)."""
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, machine_spec or MachineSpec())
        vm = helper.make("box", kind="vm", gpu_mode="none")
        tell_the_parent(root, machine_token, helper)
        try:
            yield root, operator, helper, vm, (lambda: tell_the_parent(root, machine_token, helper))
        finally:
            helper.stop()


def view(operator, vm):
    reply = operator.request("GET", app_path(vm))
    expect(reply.status == 200, f"app view gave {reply.status}: {reply.raw[:200]!r}")
    expect_schema("AppView", reply.body, "the app view")
    return reply.body


def wait_state(operator, vm, state):
    deadline = time.time() + STATE_WAIT_SECONDS
    while time.time() < deadline:
        current = view(operator, vm)
        if current["state"] == state:
            return current
        time.sleep(0.2)
    raise AssertionError(f"the app state never became {state}: {view(operator, vm)}")


def create_with_app(operator, helper, beat, app="openclaw", name="appvm"):
    """Creates a VM with the app through the panel, waits for the helper to have made it and lets the parent see it. Returns the new VM's id."""
    reply = operator.write("POST", "/api/workloads", {"name": name, "machine": MACHINE, "bundle": app, **VM})
    expect(reply.status == 202, f"create with {app} gave {reply.status}: {reply.raw[:200]!r}")
    command = reply.body["command"]["id"]
    deadline = time.time() + COMMAND_WAIT_SECONDS
    while time.time() < deadline:
        current = operator.request("GET", f"/api/commands/{command}").body["command"]
        if current["state"] == "succeeded":
            beat()
            return current["result"]["workload_id"]
        time.sleep(0.3)
    raise AssertionError("the create never succeeded")


def list_app(operator, vm):
    machines = operator.request("GET", "/api/machines").body["machines"]
    workloads = [w for machine in machines if machine["id"] == MACHINE for w in machine["workloads"]]
    return next(w for w in workloads if w["id"] == vm)["app"]


def database_of(root):
    return sqlite3.connect(f"{root.dir}/root.sqlite3")


def stored_rows(root, vm):
    database = database_of(root)
    try:
        return database.execute("SELECT COUNT(*) FROM workload_app_state WHERE workload_id = ?", (vm,)).fetchone()[0]
    finally:
        database.close()


def machine_images(operator):
    reply = operator.request("GET", f"/api/machines/{MACHINE}/images")
    expect(reply.status == 200, f"machine images gave {reply.status}")
    return {image["id"]: image for image in reply.body["images"]}


def expect_refused(reply, status, code, label):
    expect(reply.status == status and (reply.body or {}).get("error", {}).get("code") == code, f"{label}: wanted {status} {code}, got {reply.status} {reply.raw[:200]!r}")


def check_apps_are_selectable_when_the_helper_says_ready_and_disabled_with_the_update_reason_otherwise():
    with world() as (_root, operator, _helper, _vm, _beat):
        images = machine_images(operator)
        for app in ("openclaw", "hermes"):
            expect(images[app]["available"] and images[app]["ready"] and images[app]["reason"] is None, f"{app} on a helper that says ready: {images[app]}")
    with world(MachineSpec(serves_apps=False)) as (_root, operator, _helper, _vm, _beat):
        images = machine_images(operator)
        for app in ("openclaw", "hermes"):
            expect(not images[app]["available"] and images[app]["reason"] == UPDATE_HELPER, f"{app} on a helper that does not report ready: {images[app]}")
        refused = operator.write("POST", "/api/workloads", {"name": "nope", "machine": MACHINE, "bundle": "openclaw", **VM})
        expect_refused(refused, 409, "image_not_available", "create with an app the helper cannot install")
        expect(refused.body["error"]["message"] == UPDATE_HELPER, f"the refusal must say why: {refused.body}")


def check_apps_a_create_with_an_app_ends_installing_then_ready_and_the_machine_list_carries_it():
    with world() as (_root, operator, helper, _vm, beat):
        helper.engine.set_app_install("works", INSTALL_DELAY_SECONDS)
        vm = create_with_app(operator, helper, beat)
        expect(helper.engine.created_requests[-1].get("bundle") is None, f"the app must not reach the helper as an image: {helper.engine.created_requests[-1]}")
        installing = wait_state(operator, vm, "installing")
        expect(installing["app"] == "openclaw" and installing["started_at"] is not None and installing["message"] is None, f"while installing: {installing}")
        expect(list_app(operator, vm) == {"name": "openclaw", "state": "installing", "message": None}, f"machine list while installing: {list_app(operator, vm)}")
        ready = wait_state(operator, vm, "ready")
        expect(ready["version"] and ready["log_tail"] == [] and ready["message"] is None, f"when ready: {ready}")
        expect(helper.engine.apps_in(vm) == ["openclaw"], "the app must be in the VM")
        expect(list_app(operator, vm) == {"name": "openclaw", "state": "ready", "message": None}, f"machine list when ready: {list_app(operator, vm)}")
        other = next(w for m in operator.request("GET", "/api/machines").body["machines"] for w in m["workloads"] if w["id"] != vm)
        expect(other["app"] is None, f"a VM without an app must say null: {other}")


def check_apps_a_failed_install_shows_message_and_log_the_heartbeat_waits_and_retry_does_not():
    with world() as (_root, operator, helper, _vm, beat):
        helper.engine.set_app_install("fails", 0)
        vm = create_with_app(operator, helper, beat, app="hermes")
        failed = wait_state(operator, vm, "failed")
        expect(failed["message"] == FAKE_FAILURE and FAKE_LOG_LINE in failed["log_tail"] and failed["app"] == "hermes", f"failed view: {failed}")
        expect(list_app(operator, vm) == {"name": "hermes", "state": "failed", "message": FAKE_FAILURE}, f"machine list when failed: {list_app(operator, vm)}")
        installs = helper.engine.apps.installs
        beat()
        time.sleep(1)
        expect(view(operator, vm)["state"] == "failed" and helper.engine.apps.installs == installs, "the heartbeat must wait a minute after a failure")
        helper.engine.set_app_install("works", INSTALL_DELAY_SECONDS)
        retried = operator.write("POST", app_path(vm) + "/retry")
        expect(retried.status == 200 and retried.body["state"] == "installing", f"retry: {retried.status} {retried.raw[:200]!r}")
        expect_schema("AppView", retried.body, "the retry answer")
        expect(wait_state(operator, vm, "ready")["message"] is None, "after the retry")


def check_apps_audit_has_the_result_and_the_installer_checksum_but_never_the_installer_output():
    with world() as (_root, operator, helper, _vm, beat):
        helper.engine.set_app_install("fails", 0)
        vm = create_with_app(operator, helper, beat)
        wait_state(operator, vm, "failed")
        helper.engine.set_app_install("works", 0)
        operator.write("POST", app_path(vm) + "/retry")
        wait_state(operator, vm, "ready")
        audit = operator.request("GET", "/api/audit?limit=200")
        installs = [entry for entry in audit.body["entries"] if entry["action"] == "app.install"]
        text = str(installs)
        expect(len(installs) == 2 and "failed" in text and "ready" in text, f"two install entries wanted: {installs}")
        expect(MACHINE in text and vm in text and "openclaw" in text and "0123456789abcdef" in text, f"an entry misses a field: {installs}")
        expect(FAKE_LOG_LINE.encode() not in audit.raw and FAKE_FAILURE.encode() not in audit.raw, "installer output is in the audit trail")


def check_apps_a_stopped_vm_cannot_be_retried_and_a_vm_without_an_app_says_none():
    with world() as (_root, operator, helper, vm, beat):
        none = view(operator, vm)
        expect(none == {"app": None, "state": "none", "message": None, "log_tail": [], "version": None, "started_at": None}, f"a VM without an app: {none}")
        expect_refused(operator.write("POST", app_path(vm) + "/retry"), 409, "no_app", "retry without an app")
        helper.engine.set_app_install("fails", 0)
        app_vm = create_with_app(operator, helper, beat)
        wait_state(operator, app_vm, "failed")
        helper.engine.set_state("c-down", app_vm, "stop", "stopped")
        beat()
        expect_refused(operator.write("POST", app_path(app_vm) + "/retry"), 409, "not_running", "retry on a stopped VM")


def check_apps_a_helper_that_answers_404_makes_the_state_failed_with_the_update_words():
    with world() as (_root, operator, helper, _vm, beat):
        helper.engine.set_app_install("fails", 0)
        vm = create_with_app(operator, helper, beat)
        wait_state(operator, vm, "failed")
        helper.engine.spec.serves_apps = False
        expect(operator.write("POST", app_path(vm) + "/retry").status == 200, "retry")
        deadline = time.time() + STATE_WAIT_SECONDS
        while view(operator, vm)["message"] != OLD_HELPER_FAILURE and time.time() < deadline:
            time.sleep(0.2)
        old = view(operator, vm)
        expect(old["state"] == "failed" and old["message"] == OLD_HELPER_FAILURE and old["log_tail"] == [], f"old helper view: {old}")


def check_apps_unknown_machines_vms_and_odd_ids_are_404():
    with world() as (_root, operator, _helper, vm, _beat):
        for path in (app_path(vm, "nobody"), app_path("nope"), app_path("BAD%20ID"), app_path(vm, "BAD%20ID")):
            expect_refused(operator.request("GET", path), 404, "not_found", f"GET {path}")
            expect_refused(operator.write("POST", path + "/retry"), 404, "not_found", f"POST {path}/retry")


def check_apps_deleting_the_vm_removes_the_state():
    with world() as (root, operator, helper, _vm, beat):
        vm = create_with_app(operator, helper, beat)
        wait_state(operator, vm, "ready")
        expect(stored_rows(root, vm) == 1, "the app state must be stored while the VM exists")
        deleted = operator.write("POST", f"/api/machines/{MACHINE}/workloads/{vm}/delete", {"confirm": True})
        expect(deleted.status == 202, f"delete gave {deleted.status}")
        deadline = time.time() + COMMAND_WAIT_SECONDS
        while stored_rows(root, vm) and time.time() < deadline:
            time.sleep(0.3)
        expect(stored_rows(root, vm) == 0, "the deleted VM's app state is still stored")


def check_apps_routes_need_a_session_and_writes_need_origin_csrf_and_the_right_host():
    with world() as (_root, operator, helper, vm, _beat):
        anonymous = Browser(operator.root, auto_login=False)
        expect(anonymous.request("GET", app_path(vm)).status == 401, "GET without a session")
        expect(anonymous.request("POST", app_path(vm) + "/retry").status == 401, "POST without a session")
        expect(operator.request("POST", app_path(vm) + "/retry").status == 403, "POST without the CSRF token")
        expect(operator.write("POST", app_path(vm) + "/retry", origin=HOSTILE_ORIGIN).status == 403, "POST from a hostile Origin")
        expect(operator.write("POST", app_path(vm) + "/retry", headers={"Host": "evil.example"}).status == 403, "POST with a foreign Host")
        expect(operator.request("GET", app_path(vm), headers={"Host": "evil.example"}).status == 403, "GET with a foreign Host")
        expect(helper.engine.apps.installs == 0, "a refused request installed something")


def check_apps_hostile_create_bodies_are_refused():
    with world() as (_root, operator, helper, _vm, _beat):
        for bad in ("evil", "OpenClaw", "openclaw; reboot", "../openclaw", ["openclaw"], {"app": "openclaw"}):
            reply = operator.write("POST", "/api/workloads", {"name": "bad", "machine": MACHINE, "bundle": bad, **VM})
            expect(reply.status == 400, f"bundle {bad!r}: {reply.status} {reply.raw[:200]!r}")
        expect(len(helper.engine.created_requests) == 1, "a refused create reached the helper")
        expect(operator.write("POST", app_path("box") + "/retry", {"app": "evil"}).status in (200, 400, 404, 409), "a body on retry must not crash the parent")


def check_apps_retries_are_rate_limited():
    with world() as (_root, operator, _helper, vm, _beat):
        statuses = [operator.write("POST", app_path(vm) + "/retry").status for _ in range(RETRIES_PER_MINUTE + 1)]
        expect(statuses[:RETRIES_PER_MINUTE] == [409] * RETRIES_PER_MINUTE and statuses[-1] == 429, f"statuses: {statuses}")


CHECKS = [check_apps_are_selectable_when_the_helper_says_ready_and_disabled_with_the_update_reason_otherwise,
          check_apps_a_create_with_an_app_ends_installing_then_ready_and_the_machine_list_carries_it,
          check_apps_a_failed_install_shows_message_and_log_the_heartbeat_waits_and_retry_does_not,
          check_apps_audit_has_the_result_and_the_installer_checksum_but_never_the_installer_output,
          check_apps_a_stopped_vm_cannot_be_retried_and_a_vm_without_an_app_says_none,
          check_apps_a_helper_that_answers_404_makes_the_state_failed_with_the_update_words,
          check_apps_unknown_machines_vms_and_odd_ids_are_404, check_apps_deleting_the_vm_removes_the_state,
          check_apps_routes_need_a_session_and_writes_need_origin_csrf_and_the_right_host,
          check_apps_hostile_create_bodies_are_refused, check_apps_retries_are_rate_limited]
