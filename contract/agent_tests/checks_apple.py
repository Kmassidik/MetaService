"""The Apple engine against a fake `container` program: what it runs, what it remembers, and what it refuses to lose."""
import os
import time

from contract.agent_tests.support import FakeContainerWorld, apple_agent, wait_for
from contract.root_tests.support import expect

BODY = {"name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 10}


def make(agent, command_id="c-1", **changes):
    status, reply = agent.call("POST", "/v1/workloads", {"command_id": command_id, **BODY, **changes})
    expect(status == 202, f"create gave {status} {reply}")
    return wait_command(agent, command_id)


def wait_command(agent, command_id, want="succeeded"):
    return wait_for(lambda: (c := agent.call("GET", f"/v1/commands/{command_id}")[1]) and c["state"] == want and c, 20, f"command {command_id} never became {want}")


def workloads(agent):
    return agent.call("GET", "/v1/workloads")[1]["workloads"]


def check_create_runs_one_fixed_command_and_remembers_the_workload():
    with apple_agent() as agent:
        done = make(agent)
        workload_id = done["result"]["workload_id"]
        run = next(call for call in agent.world.calls() if call[0] == "run")
        expect(run[:10] == ["run", "--detach", "--name", f"ms-{workload_id}", "--cpus", "2", "--memory", "2048M", "--label", f"metaservice.id={workload_id}"], f"run call: {run[:10]}")
        flat = " ".join(" ".join(call) for call in agent.world.calls())
        expect(all(bad not in flat for bad in ("--privileged", "--cap-add", "--volume", "--publish", "demo")), "the run call has an extra flag or leaks the user's name")
        listed = workloads(agent)
        expect(len(listed) == 1 and listed[0]["name"] == "demo" and listed[0]["state"] == "running" and listed[0]["address"].startswith("192.168.65."), f"listed: {listed}")
        expect(os.stat(os.path.join(agent.state, "workloads.json")).st_mode & 0o777 == 0o600, "the workload list file is not mode 600")


def check_the_image_is_pulled_once_and_a_bad_pull_fails_cleanly():
    with apple_agent() as agent:
        make(agent, "c-1")
        make(agent, "c-2", name="second")
        pulls = [call for call in agent.world.calls() if call[:2] == ["image", "pull"]]
        expect(len(pulls) == 1, f"the image was pulled {len(pulls)} times")
    world = FakeContainerWorld(FAKE_CONTAINER_FAIL="image pull")
    with apple_agent(world) as agent:
        agent.call("POST", "/v1/workloads", {"command_id": "c-x", **BODY})
        wait_command(agent, "c-x", "failed")
        expect(workloads(agent) == [], "a failed pull left a workload behind")


def check_a_failed_run_leaves_nothing_and_frees_the_budget():
    world = FakeContainerWorld(FAKE_CONTAINER_FAIL="run")
    with apple_agent(world) as agent:
        free_before = agent.call("GET", "/v1/facts")[1]["free_disk_gb"]
        agent.call("POST", "/v1/workloads", {"command_id": "c-bad", **BODY})
        wait_command(agent, "c-bad", "failed")
        expect(workloads(agent) == [], "a failed run left a workload")
        expect(agent.call("GET", "/v1/facts")[1]["free_disk_gb"] == free_before, "a failed run kept disk reserved")
        expect(not os.path.exists(os.path.join(agent.state, "workloads.json")) or open(os.path.join(agent.state, "workloads.json")).read() == "{}", "the record was not rolled back")


def check_the_container_system_is_started_when_it_is_down_and_a_stuck_one_fails_cleanly():
    with apple_agent() as agent:
        make(agent)
        expect(any(call[:2] == ["system", "start"] for call in agent.world.calls()), "the system was never started")
    world = FakeContainerWorld(FAKE_CONTAINER_SYSTEM_STUCK="1")
    with apple_agent(world) as agent:
        agent.call("POST", "/v1/workloads", {"command_id": "c-stuck", **BODY})
        failed = wait_command(agent, "c-stuck", "failed")
        expect(workloads(agent) == [] and "error" in failed["result"], f"stuck system: {failed}")


def check_start_and_stop_go_through_the_tool():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        agent.call("POST", f"/v1/workloads/{workload_id}/stop", headers={"X-Command-Id": "c-stop"})
        wait_command(agent, "c-stop")
        expect(workloads(agent)[0]["state"] == "stopped" and workloads(agent)[0]["address"] is None, f"after stop: {workloads(agent)}")
        stop = next(call for call in agent.world.calls() if call[0] == "stop")
        expect(stop == ["stop", "--signal", "SIGRTMIN+3", "--time", "30", f"ms-{workload_id}"], f"stop call {stop}")
        agent.call("POST", f"/v1/workloads/{workload_id}/start", headers={"X-Command-Id": "c-start"})
        wait_command(agent, "c-start")
        expect(workloads(agent)[0]["state"] == "running", "not running after start")


def check_changes_made_outside_the_agent_show_up():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        agent.world.edit(lambda s: s["containers"][f"ms-{workload_id}"].update(state="stopped"))
        expect(workloads(agent)[0]["state"] == "stopped", "a container stopped from outside still shows as running")
        agent.world.edit(lambda s: s["containers"].pop(f"ms-{workload_id}"))
        expect(workloads(agent)[0]["state"] == "failed", "a vanished container is not shown as failed")
        agent.world.edit(lambda s: s["containers"].update({"ms-stranger": {"state": "running", "ip": "192.168.65.99"}, "someone-elses": {"state": "running", "ip": "192.168.65.98"}}))
        expect(len(workloads(agent)) == 1, "containers the Agent did not make appeared in its list")


def check_delete_backs_up_first_and_keeps_the_backup():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        agent.call("DELETE", f"/v1/workloads/{workload_id}", headers={"X-Command-Id": "c-del"})
        done = wait_command(agent, "c-del")
        backup = done["result"]["backup_id"]
        path = os.path.join(agent.world.backups, backup)
        expect(os.path.getsize(path) > 0 and backup.startswith(workload_id), f"backup file {backup}")
        expect(os.stat(agent.world.backups).st_mode & 0o777 == 0o700, "the backup folder is not mode 700")
        names = [call[0] for call in agent.world.calls()]
        expect(names.index("export") < names.index("delete"), "the machine was deleted before it was backed up")
        expect(workloads(agent) == [] and agent.world.state()["containers"] == {}, "the workload is still there")


def check_a_failed_or_empty_backup_stops_the_delete():
    for switch in ({"FAKE_CONTAINER_FAIL": "export"}, {"FAKE_CONTAINER_EMPTY_EXPORT": "1"}):
        world = FakeContainerWorld()
        with apple_agent(world) as agent:
            workload_id = make(agent)["result"]["workload_id"]
            agent.stop()
            world.env.update(switch)
            agent.env = world.env
            agent.start()
            agent.call("DELETE", f"/v1/workloads/{workload_id}", headers={"X-Command-Id": "c-nobackup"})
            wait_command(agent, "c-nobackup", "failed")
            expect(len(workloads(agent)) == 1 and f"ms-{workload_id}" in world.state()["containers"], f"{switch}: the workload was deleted without a backup")
            expect(not any(call[0] == "delete" for call in world.calls()), f"{switch}: the delete command ran")


def check_deleting_something_already_gone_just_clears_the_record():
    with apple_agent() as agent:
        workload_id = make(agent)["result"]["workload_id"]
        agent.world.edit(lambda s: s["containers"].pop(f"ms-{workload_id}"))
        agent.call("DELETE", f"/v1/workloads/{workload_id}", headers={"X-Command-Id": "c-gone"})
        done = wait_command(agent, "c-gone")
        expect(done["result"]["backup_id"] == "none" and workloads(agent) == [], f"gone delete: {done}")


def check_everything_survives_an_agent_restart():
    from contract.tests.bundle_source import BundleSource
    import json
    from contract.agent_tests.support import write_secret
    source = BundleSource("machine-token-for-the-test-source-0001")
    try:
        with apple_agent(extra=["--chat-port", str(__import__("contract.root_tests.support", fromlist=["_free_port"])._free_port()), "--chat-bind", "127.0.0.1"]) as agent:
            workload_id = make(agent, "c-keep")["result"]["workload_id"]
            agent.stop()
            write_secret(os.path.join(agent.state, "agent.token"), "machine-token-for-the-test-source-0001")
            write_secret(os.path.join(agent.state, "agent.json"), json.dumps({"root": source.url, "name": "x"}))
            agent.start()
            version = source.versions[0]
            agent.call("POST", "/v1/bundle/install", {"command_id": "c-b", "version": version, "sha256": source.sha[version], "workload_id": workload_id})
            wait_command(agent, "c-b")
            agent.stop()
            agent.start()
            listed = workloads(agent)
            expect(len(listed) == 1 and listed[0]["id"] == workload_id and listed[0]["bundle_version"] == version, f"after restart: {listed}")
            again = agent.call("POST", "/v1/workloads", {"command_id": "c-keep", **BODY})
            expect(again[0] == 202 and again[1]["state"] == "succeeded" and len(workloads(agent)) == 1, f"a repeated command id after a restart made another workload: {again}")
    finally:
        source.stop()


def check_a_command_running_when_the_agent_dies_is_reported_failed():
    with apple_agent() as agent:
        agent.stop()
        # a ledger left behind with a command still "running", as after a crash
        open(os.path.join(agent.state, "commands.json"), "w").write('[{"commandId":"c-crash","type":"create","state":"running","workloadId":"w-x","result":null}]')
        agent.start()
        status, command = agent.call("GET", "/v1/commands/c-crash")
        expect(status == 200 and command["state"] == "failed", f"a crashed command: {status} {command}")


def check_the_budget_counts_apple_workloads():
    with apple_agent(extra=["--ram-allowance-mb", "10000", "--ram-reserve-mb", "2000", "--disk-allowance-gb", "100", "--disk-reserve-gb", "10"]) as agent:
        before = agent.call("GET", "/v1/facts")[1]
        make(agent)
        after = agent.call("GET", "/v1/facts")[1]
        expect(before["free_ram_mb"] - after["free_ram_mb"] == 2048 and before["free_disk_gb"] - after["free_disk_gb"] == 10, f"{before['free_ram_mb']} -> {after['free_ram_mb']}")
        expect(after["capabilities"] == {"vm": True, "container": False, "gpu_in_vm": False, "gpu_in_container": False}, f"capabilities {after['capabilities']}")
        status, reply = agent.call("POST", "/v1/workloads", {"command_id": "c-ct", **BODY, "kind": "container"})
        expect(status == 409 and reply["error"]["code"] == "missing_capability", "a container was accepted on a machine that only runs VMs")


def check_without_the_container_program_the_agent_runs_and_says_what_is_missing():
    from contract.agent_tests.support import RunningAgent
    agent = RunningAgent(extra=["--engine", "apple", "--container-path", "/nonexistent/container"]).start()
    try:
        status, facts = agent.call("GET", "/v1/facts")
        expect(status == 200 and facts["os"] == "macos" and facts["cpu_cores"] >= 1, f"the machine's real facts are missing: {status} {facts}")
        expect([p["code"] for p in facts["problems"]] == ["container_tool_missing"], f"problems: {facts['problems']}")
        expect("container" in facts["problems"][0]["message"] and facts["problems"][0]["fix"], f"problem text: {facts['problems'][0]}")
        expect(facts["capabilities"] == {"vm": False, "container": False, "gpu_in_vm": False, "gpu_in_container": False}, f"capabilities {facts['capabilities']}")
        status, reply = agent.call("POST", "/v1/workloads", {"command_id": "c-no", **BODY})
        expect(status == 409 and reply["error"]["code"] == "missing_capability", f"a workload was accepted without the tool: {status} {reply}")
        expect(agent.call("GET", "/v1/workloads")[1] == {"workloads": []}, "workloads should be empty")
    finally:
        agent.stop()


CHECKS = [
    check_create_runs_one_fixed_command_and_remembers_the_workload, check_the_image_is_pulled_once_and_a_bad_pull_fails_cleanly,
    check_a_failed_run_leaves_nothing_and_frees_the_budget, check_the_container_system_is_started_when_it_is_down_and_a_stuck_one_fails_cleanly,
    check_start_and_stop_go_through_the_tool, check_changes_made_outside_the_agent_show_up, check_delete_backs_up_first_and_keeps_the_backup,
    check_a_failed_or_empty_backup_stops_the_delete, check_deleting_something_already_gone_just_clears_the_record,
    check_everything_survives_an_agent_restart, check_a_command_running_when_the_agent_dies_is_reported_failed, check_the_budget_counts_apple_workloads,
    check_without_the_container_program_the_agent_runs_and_says_what_is_missing,
]
