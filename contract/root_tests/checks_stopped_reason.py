"""Why a VM stopped, and why a VM never started: a real Root and fake helpers (agent/fake). The reason a helper reports is kept with the VM, returned on
GET /api/machines, cleaned and capped again, and gone as soon as the VM runs again or is deleted. A create that failed passes the helper's plain-words reason on."""
import copy

from contract.root_tests.checks_gpu import MACHINE, machine_like
from contract.root_tests.checks_remote_install import wait_command
from contract.root_tests.support import Browser, enrolled_machine, expect, good_heartbeat, running
from agent.fake.engine import MachineSpec
from contract.tests.support import expect_schema

ESCAPE = "\x1b"
REASON_LOG = "[!!!!!!] Failed to mount API filesystems.\nExiting PID 1..."
MAX_TAIL_BYTES = 2048
MAX_TAIL_LINES = 12
# The GPU-limit fields of a reason; the Root lists them as null when a helper did not send them.
NO_GPU_REASON = {"code": None, "message": None, "used_gb": None, "limit_gb": None}
FAIL_TEXT = "The VM did not start.\nTry 1, with systemd: it stopped right after it started (exit code 255)."


def machine_workloads(operator):
    return operator.request("GET", f"/api/machines/{MACHINE}").body["workloads"]


def check_a_vm_that_stopped_by_itself_shows_why_until_it_runs_again():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            vm = helper.make("test", kind="vm", gpu_mode="none")
            beat()
            expect(machine_workloads(operator)[0]["stopped_reason"] is None, "a running VM must show no reason (null)")
            helper.engine.quit_by_itself(vm, 255, REASON_LOG)
            beat()
            listed = machine_workloads(operator)[0]
            expect(listed["state"] == "stopped" and listed["stopped_reason"] == {**NO_GPU_REASON, "exit_code": 255, "log_tail": REASON_LOG}, f"listed: {listed}")
            helper.engine.set_state("c-up", vm, "start", "running")
            beat()
            expect(machine_workloads(operator)[0]["stopped_reason"] is None, "the reason stayed after the VM ran again")
            helper.engine.quit_by_itself(vm, None, "gone quiet")
            beat()
            expect(machine_workloads(operator)[0]["stopped_reason"] == {**NO_GPU_REASON, "exit_code": None, "log_tail": "gone quiet"}, "an unknown exit code must come back as null")
            helper.engine.delete("c-del", vm)
            beat()
            expect(machine_workloads(operator) == [], "a deleted VM is still listed")
        finally:
            helper.stop()


def check_the_helper_workload_shape_with_a_reason_fits_the_contract():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            vm = helper.make("test", kind="vm", gpu_mode="none")
            helper.engine.quit_by_itself(vm, 255, REASON_LOG)
            expect_schema("Workload", helper.engine.workloads()[0], "a workload with a reason")
            beat()
        finally:
            helper.stop()


def check_a_reason_with_hostile_text_is_cleaned_capped_and_stays_text():
    hostile = f"{ESCAPE}[31m<img src=x onerror=alert(1)>{ESCAPE}]0;t\x07\x00\n" + "\n".join(f"line {n}" for n in range(60)) + "\n" + "é" * 5000
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            vm = helper.make("test", kind="vm", gpu_mode="none")
            helper.engine.quit_by_itself(vm, 1, hostile)
            beat()
            reply = operator.request("GET", f"/api/machines/{MACHINE}")
            tail = reply.body["workloads"][0]["stopped_reason"]["log_tail"]
            expect(ESCAPE not in tail and "\x00" not in tail and "\x07" not in tail, f"control characters survived: {tail[:60]!r}")
            expect(len(tail.encode()) <= MAX_TAIL_BYTES and tail.count("\n") < MAX_TAIL_LINES, f"not capped: {len(tail.encode())} bytes")
            expect((reply.header("Content-Type") or "").startswith("application/json") and reply.header("X-Content-Type-Options") == "nosniff", "served as something other than JSON")
            helper.engine.quit_by_itself(vm, 1, "<img src=x onerror=alert(1)>")
            beat()
            expect(machine_workloads(operator)[0]["stopped_reason"]["log_tail"] == "<img src=x onerror=alert(1)>", "markup must stay the same plain text")
        finally:
            helper.stop()


def beat_with(root, token, state, **fields):
    body = copy.deepcopy(good_heartbeat())
    body["workloads"][0].update(state=state, **fields)
    return Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)


def check_a_reason_on_a_running_vm_is_dropped_and_broken_reasons_are_refused():
    with running() as root:
        operator = Browser(root)
        token = enrolled_machine(operator, MACHINE)
        expect(beat_with(root, token, "running", stopped_reason={"exit_code": 1, "log_tail": "old news"}).status == 204, "a reason on a running VM is only dropped, not refused")
        expect(operator.request("GET", f"/api/machines/{MACHINE}").body["workloads"][0]["stopped_reason"] is None, "a running VM kept a reason")
        broken = [{"exit_code": "1", "log_tail": "x"}, {"exit_code": 1, "log_tail": "x", "more": 1}, {"exit_code": 99999, "log_tail": "x"},
                  {"exit_code": 1, "log_tail": "x" * 20001}, "boom", {"exit_code": 1, "log_tail": 5}]
        for reason in broken:
            reply = beat_with(root, token, "stopped", stopped_reason=reason)
            expect(reply.status == 400, f"{str(reason)[:40]!r} gave {reply.status}")
        expect(beat_with(root, token, "stopped", init_mode="docker").status == 400, "an unknown init mode was accepted")
        expect(beat_with(root, token, "stopped", init_mode="plain", stopped_reason=None).status == 204, "a null reason and a known mode must be accepted")
        expect(operator.request("GET", f"/api/machines/{MACHINE}").body["workloads"][0]["init_mode"] == "plain", "the mode was not kept")


def check_a_create_that_failed_passes_the_plain_reason_on_cleaned():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            beat()
            helper.engine.fail_creates_with(FAIL_TEXT + f"\n{ESCAPE}[31mred{ESCAPE}[0m\x00 <b>bold</b>")
            reply = operator.write("POST", "/api/workloads", {"name": "test", "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1, "machine": MACHINE})
            expect(reply.status == 202, f"create gave {reply.status}: {reply.raw[:200]!r}")
            command = wait_command(operator, reply.body["command"]["id"], "failed")
            error = command["result"]["error"]
            expect(error.startswith(FAIL_TEXT), f"error: {error!r}")
            expect(ESCAPE not in error and "\x00" not in error, f"control characters in the reason: {error!r}")
            expect("<b>bold</b>" in error, "markup must stay as the same text")
        finally:
            helper.stop()


CHECKS = [check_a_vm_that_stopped_by_itself_shows_why_until_it_runs_again, check_the_helper_workload_shape_with_a_reason_fits_the_contract,
          check_a_reason_with_hostile_text_is_cleaned_capped_and_stays_text, check_a_reason_on_a_running_vm_is_dropped_and_broken_reasons_are_refused,
          check_a_create_that_failed_passes_the_plain_reason_on_cleaned]
