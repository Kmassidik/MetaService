"""The GPU memory limit of a container, against a real Root and a fake helper (agent/fake): the Root books the limits against the card so they never add up to
more than the card has, keeps a booking while the VM is stopped, frees it when the VM is deleted or its create fails, and relays the helper's watchdog reason."""
import copy
import json
import threading
import urllib.request

from agent.fake.engine import MachineSpec
from contract.root_tests.checks_gpu import CARD, MACHINE, GpuHelper, machine_like, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.checks_remote_install import wait_command
from contract.root_tests.support import Browser, expect, good_heartbeat, running

CARD_GB = 32
CONTAINER = {"kind": "container", "cpu": 1, "ram_mb": 512, "disk_gb": 1, "gpu_mode": "container"}
WITH_TOOLKIT = MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True)
OLD_HELPER = MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True, gpu_memory_limit=False)
CARD_WITHOUT_MEMORY = MachineSpec(vm=False, gpu=[{"vendor": "nvidia", "model": "Mystery", "memory_mb": None}], gpu_in_container=True)
OVER_LIMIT_CODE = "gpu_memory_over_limit"


def create(operator, name, gb=None, **changes):
    body = {"name": name, "machine": MACHINE, **CONTAINER, **changes}
    if gb is not None:
        body["gpu_memory_gb"] = gb
    return operator.write("POST", "/api/workloads", body)


def created(operator, beat, name, gb):
    """A container with a limit, accepted and finished; returns its workload id as the helper named it."""
    reply = create(operator, name, gb)
    expect(reply.status == 202, f"create {gb} GB gave {reply.status}: {reply.raw[:200]!r}")
    command = wait_command(operator, reply.body["command"]["id"], "succeeded")
    beat()
    return command["result"]["workload_id"]


def machine_view(operator):
    return operator.request("GET", f"/api/machines/{MACHINE}").body


def booking(operator):
    return machine_view(operator)["gpu_booking"]


def limit_of(operator, workload):
    return next(w for w in machine_view(operator)["workloads"] if w["id"] == workload)["gpu_memory_gb"]


def check_a_create_with_a_limit_books_it_and_the_machine_shows_it():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            expect(booking(operator) == {"total_gb": CARD_GB, "booked_gb": 0, "free_gb": CARD_GB}, f"before: {booking(operator)}")
            workload = created(operator, beat, "limited", 4)
            expect(booking(operator) == {"total_gb": CARD_GB, "booked_gb": 4, "free_gb": 28}, f"after: {booking(operator)}")
            expect(limit_of(operator, workload) == 4, "the workload does not show its limit")
            expect(helper.engine.created_requests[-1]["gpu_memory_gb"] == 4, f"the helper was not sent the limit: {helper.engine.created_requests[-1]}")
            plain = create(operator, "plain", None)
            wait_command(operator, plain.body["command"]["id"], "succeeded")
            beat()
            expect("gpu_memory_gb" not in helper.engine.created_requests[-1], "a create without a limit must not send one")
            expect(booking(operator)["booked_gb"] == 4, "a create without a limit booked something")
        finally:
            helper.stop()


def check_a_second_limit_that_fits_is_booked_and_one_that_does_not_is_refused_with_the_numbers():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            created(operator, beat, "first", 4)
            created(operator, beat, "second", 24)
            expect(booking(operator)["booked_gb"] == 28, f"{booking(operator)}")
            refused = create(operator, "toobig", 5)
            error = refused.body["error"]
            expect(refused.status == 409 and error["code"] == "gpu_memory_not_available" and error["free_gb"] == 4, f"{refused.status} {refused.raw[:200]!r}")
            expect(error["message"] == "Only 4 GB of the card's 32 GB is still free to book.", error["message"])
            expect(booking(operator)["booked_gb"] == 28, "a refused create booked something")
            expect(create(operator, "exact", 4).status == 202, "the last 4 GB must fit exactly")
            expect(booking(operator)["free_gb"] == 0, "the card should be fully booked")
        finally:
            helper.stop()


def check_two_creates_at_once_for_the_last_gb_have_exactly_one_winner():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            created(operator, beat, "most", CARD_GB - 1)
            statuses = []
            racers = [Browser(root) for _ in range(4)]
            for racer in racers:
                racer.csrf()

            def race(racer, name):
                statuses.append(create(racer, name, 1).status)

            threads = [threading.Thread(target=race, args=(racer, f"racer-{index}")) for index, racer in enumerate(racers)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
            expect(sorted(statuses) == [202, 409, 409, 409], f"statuses: {statuses}")
            expect(booking(operator)["booked_gb"] == CARD_GB, f"{booking(operator)}")
        finally:
            helper.stop()


def delete(operator, workload):
    reply = operator.write("POST", f"/api/machines/{MACHINE}/workloads/{workload}/delete", {"confirm": True})
    expect(reply.status == 202, f"delete gave {reply.status}")
    return wait_command(operator, reply.body["command"]["id"], "succeeded")


def check_a_stopped_vm_keeps_its_booking_and_deleting_it_frees_it():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            workload = created(operator, beat, "keeper", 8)
            stop = operator.write("POST", f"/api/machines/{MACHINE}/workloads/{workload}/stop")
            wait_command(operator, stop.body["command"]["id"], "succeeded")
            beat()
            expect(booking(operator)["booked_gb"] == 8, "a stopped VM must keep its booking")
            delete(operator, workload)
            beat()
            expect(booking(operator)["booked_gb"] == 0, f"{booking(operator)}")
            expect(create(operator, "reuse", CARD_GB).status == 202, "the freed memory could not be booked again")
        finally:
            helper.stop()


def check_a_failed_create_releases_its_booking():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            helper.engine.fail_creates_with("The container did not start.")
            reply = create(operator, "doomed", 20)
            expect(reply.status == 202, f"create gave {reply.status}")
            expect(booking(operator)["booked_gb"] == 20, "an accepted create must count while it runs")
            wait_command(operator, reply.body["command"]["id"], "failed")
            expect(booking(operator)["booked_gb"] == 0, f"{booking(operator)}")
        finally:
            helper.stop()


def check_a_limit_needs_a_container_with_the_gpu_and_a_number_from_one_to_1024():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            wrong_modes = [{"gpu_mode": "none"}, {"gpu_mode": "passthrough"}, {"kind": "vm", "gpu_mode": "none"}]
            for change in wrong_modes:
                reply = create(operator, "x", 4, **change)
                expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"{change}: {reply.status} {reply.raw[:150]!r}")
            plain_words = create(operator, "x", 4, gpu_mode="none").body["error"]["message"]
            expect(plain_words == "gpu_memory_gb can only be set when gpu_mode is container", plain_words)
            for bad in (0, -1, 1025, 4.5, "4"):
                expect(create(operator, "x", bad).status == 400, f"{bad!r} was not refused")
            expect(booking(operator)["booked_gb"] == 0, "a refused request booked something")
        finally:
            helper.stop()


def check_a_helper_without_the_capability_gets_helper_too_old_and_unknown_memory_is_refused():
    cases = {"helper_too_old": (OLD_HELPER, "Update the helper on this machine first."), "gpu_memory_unknown": (CARD_WITHOUT_MEMORY, None)}
    for code, (machine_spec, words) in cases.items():
        with running() as root:
            operator = Browser(root)
            helper, beat = machine_like(operator, root, machine_spec)
            try:
                beat()
                reply = create(operator, "x", 4)
                expect(reply.status == 409 and reply.body["error"]["code"] == code, f"{code}: {reply.status} {reply.raw[:200]!r}")
                expect(words is None or reply.body["error"]["message"] == words, reply.body["error"]["message"])
                expect(create(operator, "no-limit", None).status == 202, f"{code}: a create without a limit must still work")
                expect(machine_view(operator)["gpu_booking"] in (None, {"total_gb": CARD_GB, "booked_gb": 0, "free_gb": CARD_GB}), "booking summary")
            finally:
                helper.stop()


def use_gpu(helper, command_token, workload, used_gb):
    """The fake's watchdog hook, over HTTP as a test tool would call it."""
    request = urllib.request.Request(f"http://127.0.0.1:{helper.port}/fake/gpu-usage", data=json.dumps({"workload": workload, "used_gb": used_gb}).encode(),
                                     headers={"Authorization": f"Bearer {command_token}", "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request) as reply:
        expect(reply.status == 204, f"the hook gave {reply.status}")


def check_a_container_over_its_limit_is_stopped_and_the_reason_is_visible():
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, WITH_TOOLKIT)
        beat = lambda: tell_the_parent(root, machine_token, helper)  # noqa: E731
        try:
            beat()
            workload = created(operator, beat, "greedy", 4)
            use_gpu(helper, command_token, workload, 3.5)
            beat()
            expect(next(w for w in machine_view(operator)["workloads"] if w["id"] == workload)["state"] == "running", "under the limit must keep running")
            use_gpu(helper, command_token, workload, 5.5)
            beat()
            listed = next(w for w in machine_view(operator)["workloads"] if w["id"] == workload)
            reason = listed["stopped_reason"]
            expect(listed["state"] == "stopped" and reason["code"] == OVER_LIMIT_CODE, f"{listed}")
            expect(reason["used_gb"] == 5.5 and reason["limit_gb"] == 4 and "GPU memory" in reason["message"], f"{reason}")
            expect(reason["exit_code"] is None and reason["log_tail"] == "", f"{reason}")
            expect(booking(operator)["booked_gb"] == 4, "a stopped container keeps its booking")
            start = operator.write("POST", f"/api/machines/{MACHINE}/workloads/{workload}/start")
            wait_command(operator, start.body["command"]["id"], "succeeded")
            beat()
            expect(next(w for w in machine_view(operator)["workloads"] if w["id"] == workload)["stopped_reason"] is None, "the reason stayed after it ran again")
        finally:
            helper.stop()


def check_the_booking_survives_heartbeats_that_rewrite_the_workloads():
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, WITH_TOOLKIT)
        beat = lambda: tell_the_parent(root, machine_token, helper)  # noqa: E731
        try:
            beat()
            workload = created(operator, beat, "steady", 6)
            beat()
            beat()
            expect(booking(operator)["booked_gb"] == 6 and limit_of(operator, workload) == 6, f"{booking(operator)}")
            token = machine_token
            empty = copy.deepcopy(good_heartbeat())
            empty["workloads"] = []
            facts = helper.engine.facts()
            empty["facts"] = {key: facts[key] for key in ("os", "arch", "cpu_cores", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities")}
            reply = Browser(root).request("POST", "/v1/agents/heartbeat", empty, headers={"Authorization": f"Bearer {token}"}, origin=None)
            expect(reply.status == 204, f"heartbeat gave {reply.status}")
            expect(booking(operator)["booked_gb"] == 6, "a heartbeat without the VM freed its booking")
        finally:
            helper.stop()


def check_the_create_audit_entry_names_the_limit():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            created(operator, beat, "audited", 4)
            plain = create(operator, "unlimited", None)
            wait_command(operator, plain.body["command"]["id"], "succeeded")
            entries = [e for e in operator.request("GET", "/api/audit").body["entries"] if e["action"] == "workload.create"]
            details = [json.loads(e["detail"]) for e in entries]
            expect(any(d.get("gpu_memory_gb") == "4" and d.get("name") == "audited" for d in details), f"{details}")
            expect(all("gpu_memory_gb" not in d for d in details if d.get("name") == "unlimited"), f"{details}")
        finally:
            helper.stop()


def check_creating_with_a_limit_has_the_same_guards_as_any_create():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, WITH_TOOLKIT)
        try:
            beat()
            body = {"name": "guarded", "machine": MACHINE, **CONTAINER, "gpu_memory_gb": 4}
            expect(Browser(root, auto_login=False).request("POST", "/api/workloads", body).status == 401, "no session must be 401")
            expect(operator.request("POST", "/api/workloads", body).status == 403, "no CSRF token must be 403")
            expect(operator.write("POST", "/api/workloads", body, origin="http://evil.example").status == 403, "a foreign Origin must be 403")
            expect(booking(operator)["booked_gb"] == 0, "a refused create booked something")
        finally:
            helper.stop()


CHECKS = [check_a_create_with_a_limit_books_it_and_the_machine_shows_it, check_a_second_limit_that_fits_is_booked_and_one_that_does_not_is_refused_with_the_numbers,
          check_two_creates_at_once_for_the_last_gb_have_exactly_one_winner, check_a_stopped_vm_keeps_its_booking_and_deleting_it_frees_it,
          check_a_failed_create_releases_its_booking, check_a_limit_needs_a_container_with_the_gpu_and_a_number_from_one_to_1024,
          check_a_helper_without_the_capability_gets_helper_too_old_and_unknown_memory_is_refused, check_a_container_over_its_limit_is_stopped_and_the_reason_is_visible,
          check_the_booking_survives_heartbeats_that_rewrite_the_workloads, check_the_create_audit_entry_names_the_limit, check_creating_with_a_limit_has_the_same_guards_as_any_create]
