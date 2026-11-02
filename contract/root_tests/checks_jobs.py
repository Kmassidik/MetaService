"""Long actions as jobs: a delete that takes a while shows its step, a second delete of the same VM is refused, and the user who started it is told when it ends.
A real Root and a fake helper (agent/fake). The helper's delete is held "running" by the test and released later, so the steps can be seen.
The time limit (30 minutes) and the lost contact check (5 minutes of silence) are covered by the unit tests, not here: they are too slow for a black-box run."""
import time

from agent.fake.engine import MachineSpec
from contract.root_tests.checks_gpu import MACHINE, machine_like
from contract.root_tests.checks_remote_install import wait_command
from contract.root_tests.support import Browser, expect, running
from contract.tests.support import expect_schema

BACKING_UP = "Backing up (this can take several minutes for big disks)"
ALREADY_DELETING = "This machine is already being deleted."


def hold_deletes(helper):
    """Makes the helper's delete answer 'running' with a step, and returns a function that ends it the way a helper does."""
    engine = helper.engine

    def slow_delete(command_id, workload_id):
        record = {"command_id": command_id, "type": "delete", "state": "running", "workload_id": workload_id, "result": None, "step": BACKING_UP}
        engine._commands[command_id] = record
        return dict(record)

    def finish(command_id, workload_id, ok):
        record = engine._commands[command_id]
        record.update({"state": "succeeded" if ok else "failed", "result": {"backup_id": "b-1"} if ok else {"error": "the machine could not delete the workload"}})
        record["step"] = "Done" if ok else record["step"]
        if ok:
            engine._workloads.pop(workload_id, None)

    engine.delete = slow_delete
    return finish


def wait_for(read, done, seconds=20):
    deadline = time.time() + seconds
    while time.time() < deadline:
        value = read()
        if done(value):
            return value
        time.sleep(0.3)
    raise AssertionError(f"never reached the expected point: {value}")


def notifications(operator, query=""):
    reply = operator.request("GET", f"/api/notifications{query}")
    expect(reply.status == 200, f"notifications gave {reply.status}: {reply.raw[:200]!r}")
    expect_schema("NotificationPage", reply.body, "the notification page")
    return reply.body


def delete_request(operator, vm):
    return operator.write("POST", f"/api/machines/{MACHINE}/workloads/{vm}/delete", {"confirm": True})


def check_a_running_delete_shows_its_step_refuses_a_second_delete_and_tells_the_user():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            vm = helper.make("victim", kind="vm", gpu_mode="none")
            beat()
            finish = hold_deletes(helper)
            first = delete_request(operator, vm)
            expect(first.status == 202, f"first delete gave {first.status}: {first.raw[:200]!r}")
            command_id = first.body["command"]["id"]
            expect(first.body["command"]["step"] is None or isinstance(first.body["command"]["step"], str), "step is a string or null")
            second = delete_request(operator, vm)
            expect(second.status == 409 and second.body["error"]["code"] == "already_deleting", f"second delete: {second.status} {second.raw[:200]!r}")
            expect(second.body["error"]["message"] == ALREADY_DELETING, f"message: {second.body['error']['message']!r}")
            running_row = wait_for(lambda: operator.request("GET", f"/api/commands/{command_id}").body["command"], lambda row: row["step"] == BACKING_UP)
            expect_schema("PanelCommand", running_row, "a running job")
            expect(running_row["state"] == "running" and running_row["step_at"] is not None, f"row: {running_row}")
            expect(notifications(operator)["unread_count"] == 0, "no notification while the job runs")
            finish(command_id, vm, True)
            done = wait_command(operator, command_id, "succeeded", seconds=20)
            expect(done["step"] == "Done", f"step at the end: {done['step']!r}")
            page = notifications(operator)
            expect(page["total"] == 1 and page["unread_count"] == 1, f"page: {page}")
            row = page["notifications"][0]
            expect(row["kind"] == "job_succeeded" and row["command_id"] == command_id and row["read_at"] is None, f"row: {row}")
            expect(notifications(operator, "?unread=true")["total"] == 1, "the unread filter")
            marked = operator.write("POST", "/api/notifications/read", {"ids": [row["id"]]})
            expect(marked.status == 200 and marked.body == {"marked": 1, "unread_count": 0}, f"mark read: {marked.status} {marked.raw[:200]!r}")
            expect(notifications(operator, "?unread=true")["total"] == 0, "nothing unread now")
            beat()
            expect(delete_request(operator, vm).status == 404, "a deleted VM is gone, not 'already deleting'")
        finally:
            helper.stop()


def check_notification_routes_refuse_bad_input_and_need_a_session():
    with running() as root:
        operator = Browser(root)
        anonymous = Browser(root, auto_login=False)
        operator.request("GET", "/api/notifications")
        expect(anonymous.request("GET", "/api/notifications").status == 401, "reading needs a session")
        expect(operator.request("GET", "/api/notifications?page_size=101").status == 400, "page_size cap")
        expect(operator.request("GET", "/api/notifications?unread=maybe").status == 400, "unread must be true or false")
        for body in ({}, {"all": False}, {"ids": []}, {"ids": [1], "all": True}):
            reply = operator.write("POST", "/api/notifications/read", body)
            expect(reply.status == 400 and reply.body["error"]["code"] == "invalid_input", f"{body}: {reply.status} {reply.raw[:200]!r}")
        everything = operator.write("POST", "/api/notifications/read", {"all": True})
        expect(everything.status == 200 and everything.body == {"marked": 0, "unread_count": 0}, f"mark all: {everything.raw[:200]!r}")


CHECKS = [check_a_running_delete_shows_its_step_refuses_a_second_delete_and_tells_the_user, check_notification_routes_refuse_bad_input_and_need_a_session]
