"""The Linux Agent's Incus engine against a fake `incus` program: what it runs, what it keeps, and what it refuses to lose."""
import json
import os

from contract.agent_tests.support import FakeIncusWorld, RunningAgent, wait_for, write_secret
from contract.root_tests.support import _free_port, expect
from contract.tests.bundle_source import BundleSource

BODY = {"name": "demo", "kind": "container", "cpu": 2, "ram_mb": 2048, "disk_gb": 10}


def incus_agent(world=None, extra=None):
    world = world or FakeIncusWorld()
    agent = RunningAgent(extra=world.agent_args() + (extra or []), env=world.env)
    agent.world = world
    return agent.start()


def make(agent, command_id="c-1", **changes):
    status, reply = agent.call("POST", "/v1/workloads", {"command_id": command_id, **BODY, **changes})
    expect(status == 202, f"create gave {status} {reply}")
    return wait_command(agent, command_id)


def wait_command(agent, command_id, want="succeeded"):
    return wait_for(lambda: (c := agent.call("GET", f"/v1/commands/{command_id}")[1]) and c["state"] == want and c, 30, f"command {command_id} never became {want}")


def workloads(agent):
    return agent.call("GET", "/v1/workloads")[1]["workloads"]


def with_agent(test):
    def run():
        agent = incus_agent()
        try:
            test(agent)
        finally:
            agent.stop()
    run.__name__ = test.__name__
    return run


@with_agent
def check_create_runs_one_fixed_launch_and_the_instance_carries_the_numbers(agent):
    workload_id = make(agent)["result"]["workload_id"]
    launch = next(call for call in agent.world.calls() if call[0] == "launch")
    expect(launch[:3] == ["launch", "images:ubuntu/24.04", f"ms-{workload_id}"] and "--vm" not in launch, f"launch call: {launch[:5]}")
    for needed in ("limits.cpu=2", "limits.memory=2048MiB", "root,size=10GiB", f"user.metaservice.id={workload_id}"):
        expect(needed in launch, f"launch lacks {needed}")
    flat = " ".join(" ".join(call) for call in agent.world.calls())
    expect(all(bad not in flat for bad in ("privileged", "raw.lxc", "--target")), "the launch has a risky setting")
    listed = workloads(agent)
    expect(len(listed) == 1 and listed[0]["name"] == "demo" and listed[0]["state"] == "running" and listed[0]["address"].startswith("10.77.0."), f"listed: {listed}")
    expect((listed[0]["cpu"], listed[0]["ram_mb"], listed[0]["disk_gb"]) == (2, 2048, 10), "the numbers did not come back from the instance")


@with_agent
def check_vms_need_kvm_and_gpu_modes_need_a_gpu(agent):
    can_vm = agent.call("GET", "/v1/facts")[1]["capabilities"]["vm"]
    status, reply = agent.call("POST", "/v1/workloads", {"command_id": "c-vm", **BODY, "kind": "vm"})
    if can_vm:
        wait_command(agent, "c-vm")
        launch = next(call for call in agent.world.calls() if call[0] == "launch")
        expect("--vm" in launch, "a VM was launched without --vm")
    else:
        expect(status == 409 and reply["error"]["code"] == "missing_capability", f"a VM was accepted without KVM: {status} {reply}")
    status, reply = agent.call("POST", "/v1/workloads", {"command_id": "c-g", **BODY, "gpu_mode": "container"})
    expect(status == 409 and reply["error"]["code"] == "missing_capability", f"this machine has no GPU: {status} {reply}")


@with_agent
def check_a_failed_launch_leaves_nothing_and_frees_the_budget(agent):
    agent.world.env["FAKE_INCUS_FAIL"] = "launch"
    agent.stop()
    agent.env = agent.world.env
    agent.start()
    free = agent.call("GET", "/v1/facts")[1]["free_disk_gb"]
    agent.call("POST", "/v1/workloads", {"command_id": "c-bad", **BODY})
    wait_command(agent, "c-bad", "failed")
    expect(workloads(agent) == [] and agent.call("GET", "/v1/facts")[1]["free_disk_gb"] == free, "a failed launch left something behind")
    expect(agent.world.state() is None or agent.world.state()["instances"] == {}, "a half-made instance was left in Incus")


@with_agent
def check_start_and_stop_go_through_the_tool(agent):
    workload_id = make(agent)["result"]["workload_id"]
    agent.call("POST", f"/v1/workloads/{workload_id}/stop", headers={"X-Command-Id": "c-stop"})
    wait_command(agent, "c-stop")
    expect(workloads(agent)[0]["state"] == "stopped" and workloads(agent)[0]["address"] is None, f"after stop: {workloads(agent)}")
    stop = next(call for call in agent.world.calls() if call[0] == "stop")
    expect(stop == ["stop", f"ms-{workload_id}", "--timeout", "30"], f"stop call {stop}")
    agent.call("POST", f"/v1/workloads/{workload_id}/start", headers={"X-Command-Id": "c-start"})
    wait_command(agent, "c-start")
    expect(workloads(agent)[0]["state"] == "running", "not running after start")


@with_agent
def check_changes_made_outside_the_agent_show_up_and_strangers_do_not(agent):
    workload_id = make(agent)["result"]["workload_id"]
    import fcntl
    with open(agent.world.state_file + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = agent.world.state()
        state["instances"][f"ms-{workload_id}"]["status"] = "Stopped"
        state["instances"]["someone-elses"] = {"status": "Running", "type": "container", "config": {}, "ip": "10.77.0.99"}
        json.dump(state, open(agent.world.state_file, "w"))
    listed = workloads(agent)
    expect(len(listed) == 1 and listed[0]["state"] == "stopped", f"outside change: {listed}")


@with_agent
def check_delete_backs_up_first_and_keeps_the_backup(agent):
    workload_id = make(agent)["result"]["workload_id"]
    agent.call("DELETE", f"/v1/workloads/{workload_id}", headers={"X-Command-Id": "c-del"})
    backup = wait_command(agent, "c-del")["result"]["backup_id"]
    expect(os.path.getsize(os.path.join(agent.world.backups, backup)) > 0 and backup.startswith(workload_id), f"backup {backup}")
    names = [call[0] for call in agent.world.calls()]
    expect(names.index("export") < names.index("delete"), "deleted before the backup")
    expect(workloads(agent) == [] and agent.world.state()["instances"] == {}, "the workload is still there")


def check_a_failed_or_empty_backup_stops_the_delete():
    for switch in ({"FAKE_INCUS_FAIL": "export"}, {"FAKE_INCUS_EMPTY_EXPORT": "1"}):
        world = FakeIncusWorld()
        agent = incus_agent(world)
        try:
            workload_id = make(agent)["result"]["workload_id"]
            agent.stop()
            world.env.update(switch)
            agent.env = world.env
            agent.start()
            agent.call("DELETE", f"/v1/workloads/{workload_id}", headers={"X-Command-Id": "c-nobackup"})
            wait_command(agent, "c-nobackup", "failed")
            expect(len(workloads(agent)) == 1 and not any(call[0] == "delete" for call in world.calls()), f"{switch}: deleted without a backup")
        finally:
            agent.stop()


def check_everything_survives_an_agent_restart_and_a_workload_gets_the_bundle():
    source = BundleSource("machine-token-for-the-test-source-0001")
    agent = incus_agent(extra=["--chat-port", str(_free_port()), "--chat-bind", "127.0.0.1"])
    try:
        workload_id = make(agent, "c-keep")["result"]["workload_id"]
        agent.stop()
        write_secret(os.path.join(agent.state, "agent.token"), "machine-token-for-the-test-source-0001")
        write_secret(os.path.join(agent.state, "agent.json"), json.dumps({"root": source.url, "name": "x"}))
        agent.start()
        version = source.versions[0]
        agent.call("POST", "/v1/bundle/install", {"command_id": "c-b", "version": version, "sha256": source.sha[version], "workload_id": workload_id})
        wait_command(agent, "c-b")
        calls = agent.world.calls()
        pushes, runs = [c for c in calls if c[:2] == ["file", "push"]], [c for c in calls if c[0] == "exec"]
        expect(len(pushes) == 2 and len(runs) == 1 and "MS_VERSION=" + version in runs[0], f"calls: {[c[:2] for c in calls]}")
        key = agent.call("GET", "/v1/commands/c-b")[1]["result"]["chat_key"]
        expect(all(key not in " ".join(c) for c in calls), "the chat key is in a command-line argument")
        agent.stop()
        agent.start()
        listed = workloads(agent)
        expect(len(listed) == 1 and listed[0]["bundle_version"] == version, f"after restart: {listed}")
        again = agent.call("POST", "/v1/workloads", {"command_id": "c-keep", **BODY})
        expect(again[0] == 202 and again[1]["state"] == "succeeded" and len(workloads(agent)) == 1, f"a repeated command id made another workload: {again}")
    finally:
        agent.stop()
        source.stop()


def check_the_agent_will_not_start_without_incus():
    one = RunningAgent(extra=["--engine", "incus", "--incus-path", "/nonexistent/incus"])
    try:
        one.start()
    except AssertionError:
        code, text = one.early_exit
        expect(code != 0 and "incus" in text, f"exit {code}: {text[:100]}")
        return
    finally:
        one.stop()
    raise AssertionError("the Agent started without incus")


def problem_codes(agent):
    status, facts = agent.call("GET", "/v1/facts")
    expect(status == 200, f"facts gave {status}")
    return [p["code"] for p in facts["problems"]]


def check_a_bridge_the_firewall_blocks_is_reported_with_the_fix_and_clears_when_fixed():
    world = FakeIncusWorld().with_firewall("no zone")
    agent = incus_agent(world)
    try:
        expect(problem_codes(agent) == ["bridge_blocked_by_firewall"], f"problems: {problem_codes(agent)}")
        problem = agent.call("GET", "/v1/facts")[1]["problems"][0]
        expect("incusbr0" in problem["message"] and "setup --yes" in problem["fix"], f"problem text: {problem}")
        world.set_zone("trusted")
        expect(problem_codes(agent) == [], "the problem stayed after the zone was fixed")
    finally:
        agent.stop()


def check_a_ready_host_reports_no_problems_with_or_without_a_firewall():
    for world in (FakeIncusWorld().with_firewall("trusted"), FakeIncusWorld().with_firewall("no zone", running=False), FakeIncusWorld()):
        agent = incus_agent(world)
        try:
            expect(problem_codes(agent) == [], f"problems: {problem_codes(agent)}")
        finally:
            agent.stop()


def check_incus_that_cannot_be_used_is_reported_as_the_one_problem():
    world = FakeIncusWorld(FAKE_INCUS_FAIL="network list").with_firewall("no zone")
    agent = incus_agent(world)
    try:
        expect(problem_codes(agent) == ["incus_unreachable"], f"problems: {problem_codes(agent)}")
    finally:
        agent.stop()


CHECKS = [
    check_create_runs_one_fixed_launch_and_the_instance_carries_the_numbers, check_vms_need_kvm_and_gpu_modes_need_a_gpu,
    check_a_failed_launch_leaves_nothing_and_frees_the_budget, check_start_and_stop_go_through_the_tool,
    check_changes_made_outside_the_agent_show_up_and_strangers_do_not, check_delete_backs_up_first_and_keeps_the_backup,
    check_a_failed_or_empty_backup_stops_the_delete, check_everything_survives_an_agent_restart_and_a_workload_gets_the_bundle,
    check_the_agent_will_not_start_without_incus, check_a_bridge_the_firewall_blocks_is_reported_with_the_fix_and_clears_when_fixed,
    check_a_ready_host_reports_no_problems_with_or_without_a_firewall, check_incus_that_cannot_be_used_is_reported_as_the_one_problem,
]
