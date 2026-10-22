"""A VM is only "created" once it has answered: the two tries (systemd, then plain), the reason a VM gave for stopping, and what a stopped VM reports."""
import time

from contract.agent_tests.checks_apple import make, wait_command, workloads
from contract.agent_tests.support import FakeContainerWorld, apple_agent, wait_for
from contract.root_tests.support import expect

BODY = {"name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10}
ESCAPE = "\x1b"


def runs(agent):
    return [call for call in agent.world.calls() if call[0] == "run"]


def failed_message(agent, command_id="c-fail"):
    agent.call("POST", "/v1/workloads", {"command_id": command_id, **BODY})
    return wait_command(agent, command_id, "failed")["result"]["error"]


def check_a_vm_is_created_only_after_it_answered_and_comes_up_with_systemd():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        calls = agent.world.calls()
        expect(["exec", f"ms-{workload_id}", "cat", "/metaservice-init-mode"] in calls, "the helper never asked the VM whether it had started")
        listed = workloads(agent)[0]
        expect(listed["state"] == "running" and listed["init_mode"] == "systemd" and "stopped_reason" not in listed, f"listed: {listed}")
        expect(len(runs(agent)) == 1, "a VM that works was started more than once")


def check_the_first_try_has_the_two_rights_systemd_needs():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="systemd-needs-caps")) as agent:
        make(agent)
        first = runs(agent)[0]
        expect(first.count("--cap-add") == 2 and "NET_ADMIN" in first and "SYS_ADMIN" in first, f"first run: {first[:14]}")
        expect(workloads(agent)[0]["init_mode"] == "systemd", "without the rights the fake VM quits; with them it must run systemd")


def check_when_systemd_quits_the_vm_is_made_again_without_it_and_says_so():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="systemd-dies")) as agent:
        workload_id = make(agent)["result"]["workload_id"]
        both = runs(agent)
        expect(len(both) == 2, f"expected two tries, saw {len(both)}")
        expect("--cap-add" in both[0] and "--cap-add" not in both[1], "the plain try must not carry extra rights")
        expect("exec sleep infinity" in both[1][-1] and "apt-get" not in both[1][-1], "the second try is not the plain script")
        expect(any(call[0] == "delete" for call in agent.world.calls()), "the VM that quit was not removed before the second try")
        listed = workloads(agent)[0]
        expect(listed["state"] == "running" and listed["init_mode"] == "plain" and listed["id"] == workload_id, f"listed: {listed}")
        expect(len(agent.world.state()["containers"]) == 1, "a second container was left behind")


def check_when_both_tries_fail_the_create_fails_with_what_each_one_printed():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="both-die")) as agent:
        message = failed_message(agent)
        expect(message.startswith("The VM did not start."), f"message: {message}")
        expect("Try 1, with systemd: it stopped right after it started (exit code 255)" in message, message)
        expect("Failed to mount API filesystems" in message and "Try 2, without systemd" in message, message)
        expect(ESCAPE not in message and "memory threshold" not in message, f"escape sequences or noise in the message: {message!r}")
        expect(workloads(agent) == [] and agent.world.state()["containers"] == {}, "a failed create left a workload or a container")
        expect(len(message.encode()) < 6000, "the message is not capped")


def check_a_vm_that_quits_two_seconds_after_it_started_fails_the_create_with_the_reason():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="late-exit"), extra=["--settle-seconds", "4"]) as agent:
        message = failed_message(agent)
        expect("it stopped right after it started (exit code 1)" in message and "Segmentation fault" in message, message)
        expect(workloads(agent) == [], "a VM that quit was kept")


def check_a_vm_that_never_answers_fails_the_create_in_plain_words():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="never-answers"), extra=["--ready-seconds", "3"]) as agent:
        message = failed_message(agent)
        expect(message.count("it did not start in time (3 seconds)") == 2, message)
        expect(workloads(agent) == [] and agent.world.state()["containers"] == {}, "a VM that never answered was kept")


def check_a_vm_is_provisioning_while_it_is_being_waited_for():
    with apple_agent(world=FakeContainerWorld(FAKE_CONTAINER_BOOT="never-answers"), extra=["--ready-seconds", "4"]) as agent:
        agent.call("POST", "/v1/workloads", {"command_id": "c-wait", **BODY})
        seen = wait_for(lambda: [w["state"] for w in workloads(agent)] or None, 5, "the VM was never listed while it started")
        expect(seen == ["provisioning"], f"a VM that has not answered must be provisioning, not running: {seen}")
        wait_command(agent, "c-wait", "failed")


def stop_by_itself(world, workload_id, exit_code=3, log="out of memory\n", boot_log=""):
    world.edit(lambda s: s["containers"][f"ms-{workload_id}"].update(state="stopped", exit_code=exit_code, log=log, boot_log=boot_log))


def check_a_vm_that_stops_by_itself_reports_why_and_the_note_goes_when_it_runs_again():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        stop_by_itself(agent.world, workload_id)
        listed = workloads(agent)[0]
        expect(listed["state"] == "stopped" and listed["stopped_reason"] == {"exit_code": 3, "log_tail": "out of memory"}, f"listed: {listed}")
        looks = [call for call in agent.world.calls() if call[0] == "logs"]
        workloads(agent)
        expect(len([call for call in agent.world.calls() if call[0] == "logs"]) == len(looks), "the log was read again for the same stop")
        expect(["logs", "--boot", f"ms-{workload_id}"] in looks and ["logs", f"ms-{workload_id}"] in looks, f"log calls: {looks}")
        agent.call("POST", f"/v1/workloads/{workload_id}/start", headers={"X-Command-Id": "c-again"})
        wait_command(agent, "c-again")
        again = workloads(agent)[0]
        expect(again["state"] == "running" and "stopped_reason" not in again, f"after start: {again}")


def check_a_vm_the_helper_was_told_to_stop_has_no_reason():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        agent.call("POST", f"/v1/workloads/{workload_id}/stop", headers={"X-Command-Id": "c-off"})
        wait_command(agent, "c-off")
        listed = workloads(agent)[0]
        expect(listed["state"] == "stopped" and "stopped_reason" not in listed, f"a stop the panel asked for has a reason: {listed}")
        expect(not any(call[0] == "logs" for call in agent.world.calls()), "the log of a VM that was stopped on request was read")


def check_the_reason_is_cut_down_to_plain_text():
    hostile = f"{ESCAPE}[31m<script>alert(1)</script>{ESCAPE}]0;title\x07\x00" + "\n".join(f"line {n}" for n in range(60)) + "\n" + "é" * 3000
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        stop_by_itself(agent.world, workload_id, log=hostile)
        tail = workloads(agent)[0]["stopped_reason"]["log_tail"]
        expect(ESCAPE not in tail and "\x00" not in tail and "\x07" not in tail, f"control characters survived: {tail[:80]!r}")
        expect(len(tail.encode()) <= 2048 and tail.count("\n") <= 11, f"the tail is not capped: {len(tail.encode())} bytes, {tail.count(chr(10))} breaks")
        stop_by_itself(agent.world, workload_id, log="<script>alert(1)</script>")
        agent.stop()
        agent.start()
        expect(workloads(agent)[0]["stopped_reason"]["log_tail"] == "<script>alert(1)</script>", "markup must come back as the same plain text")


CHECKS = [
    check_a_vm_is_created_only_after_it_answered_and_comes_up_with_systemd, check_the_first_try_has_the_two_rights_systemd_needs,
    check_when_systemd_quits_the_vm_is_made_again_without_it_and_says_so, check_when_both_tries_fail_the_create_fails_with_what_each_one_printed,
    check_a_vm_that_quits_two_seconds_after_it_started_fails_the_create_with_the_reason, check_a_vm_that_never_answers_fails_the_create_in_plain_words,
    check_a_vm_is_provisioning_while_it_is_being_waited_for, check_a_vm_that_stops_by_itself_reports_why_and_the_note_goes_when_it_runs_again,
    check_a_vm_the_helper_was_told_to_stop_has_no_reason, check_the_reason_is_cut_down_to_plain_text,
]
