"""Operator -> Root -> Agent -> engine, and back: placement, space, commands, actions and what survives."""
import os
import stat
import time

from contract.agent_tests.support import FakeContainerWorld, wait_for
from contract.root_tests.support import Browser, expect
from contract.system_tests.support import world


def check_a_request_through_the_root_creates_a_workload_on_the_machine():
    with world() as w:
        w.add_machine("mini")
        reply = w.create(name="demo")
        expect(reply.status == 202 and reply.body["command"]["machine"] == "mini" and reply.body["command"]["type"] == "create", f"reply: {reply.status} {reply.body}")
        done = w.wait_command(reply.body["command"]["id"])
        expect(done["result"]["workload_id"].startswith("w-"), f"result {done['result']}")
        wait_for(lambda: any(x["name"] == "demo" and x["state"] == "running" for x in w.view("mini")["workloads"]), 10, "the Root never saw the new workload")
        actions = [e["action"] for e in w.operator.request("GET", "/api/audit").body["entries"]]
        expect("workload.create" in actions and "workload.create_succeeded" in actions, f"audit: {actions[:8]}")


def check_placement_takes_the_machine_with_the_most_room_and_honors_a_choice():
    with world() as w:
        w.add_machine("small", ram_mb=8000)
        w.add_machine("roomy", ram_mb=30000)
        expect(w.make(name="a")[0] == "roomy", "the roomier machine was not chosen")
        expect(w.make(name="b", machine="small")[0] == "small", "a named machine was not honored")
        for body, status in (({"machine": "ghost"}, 404), ({"machine": "../x"}, 400), ({"machine": "Bad Name"}, 400)):
            expect(w.create(name="c", **body).status == status, f"machine {body}: wanted {status}")


def check_the_root_refuses_what_fits_nowhere_and_says_why():
    with world() as w:
        w.add_machine("mini", engine="apple", ram_mb=8000, ram_reserve=2000)
        reply = w.create(ram_mb=9000)
        error = reply.body["error"]
        expect(reply.status == 409 and error["code"] == "not_enough_room" and error["resource"] == "ram_mb" and (error["needed"], error["free"]) == (9000, 6000), f"{reply.status} {reply.body}")
        reply = w.create(disk_gb=500)
        expect(reply.status == 409 and reply.body["error"]["resource"] == "disk_gb", f"disk: {reply.body}")
        reply = w.create(kind="container")
        expect(reply.status == 409 and reply.body["error"]["code"] == "missing_capability", f"container on a VM-only machine: {reply.body}")
        expect(not any(call[0] == "run" for call in w.machines["mini"].container.calls()), "a refused request reached the machine")
        expect(w.operator.request("GET", "/api/commands").body["commands"] == [], "a refused request left a command behind")


def check_two_requests_in_a_row_cannot_take_the_same_room():
    with world() as w:
        w.add_machine("mini", ram_mb=5000, ram_reserve=1000, heartbeat=3600)
        first, second = w.create(name="one", ram_mb=3000), w.create(name="two", ram_mb=3000)
        expect(first.status == 202, f"the first request gave {first.status}")
        expect(second.status == 409 and second.body["error"]["free"] == 1000, f"the second took the same room: {second.status} {second.body}")
        expect(len(w.operator.request("GET", "/api/commands").body["commands"]) == 1, "the Root sent the second request on instead of refusing it itself")


def check_a_stale_view_is_corrected_by_the_agents_own_check():
    with world() as w:
        mini = w.add_machine("mini", ram_mb=8000, ram_reserve=2000, heartbeat=3600)
        import http.client
        import json
        connection = http.client.HTTPConnection("127.0.0.1", mini.agent.port, timeout=10)
        connection.request("POST", "/v1/workloads", json.dumps({"command_id": "direct-1", "name": "sneaky", "kind": "vm", "cpu": 1, "ram_mb": 5000, "disk_gb": 5}),
                           {"Authorization": f"Bearer {mini.command_token}", "Content-Type": "application/json"})
        expect(connection.getresponse().status == 202, "the direct create failed")
        reply = w.create(name="late", ram_mb=4000)
        error = reply.body["error"]
        expect(reply.status == 409 and error["resource"] == "ram_mb" and error["free"] == 1000, f"the Agent's numbers were not passed on: {reply.status} {reply.body}")
        failed = [c for c in w.operator.request("GET", "/api/commands").body["commands"] if c["state"] == "failed"]
        expect(len(failed) == 1, f"the refused command was not recorded as failed: {failed}")


def check_start_stop_and_a_confirmed_delete_with_a_backup():
    with world() as w:
        mini = w.add_machine("mini", engine="apple")
        _, workload = w.make(name="demo")
        base = f"/api/machines/mini/workloads/{workload}"
        w.wait_command(w.operator.write("POST", base + "/stop").body["command"]["id"])
        wait_for(lambda: w.view("mini")["workloads"][0]["state"] == "stopped", 10, "the Root never saw it stopped")
        w.wait_command(w.operator.write("POST", base + "/start").body["command"]["id"])
        wait_for(lambda: w.view("mini")["workloads"][0]["state"] == "running", 10, "the Root never saw it running")
        for body in (None, {}, {"confirm": False}, {"confirm": "yes"}):
            expect(w.operator.write("POST", base + "/delete", body).status == 400, f"delete without a real confirm was accepted: {body}")
        expect(len(w.view("mini")["workloads"]) == 1, "an unconfirmed delete removed the workload")
        done = w.wait_command(w.operator.write("POST", base + "/delete", {"confirm": True}).body["command"]["id"])
        backup = os.path.join(mini.container.backups, done["result"]["backup_id"])
        expect(os.path.getsize(backup) > 0, "no backup file")
        wait_for(lambda: w.view("mini")["workloads"] == [], 10, "the Root still lists the deleted workload")


def check_actions_need_the_host_csrf_and_a_known_workload():
    with world() as w:
        w.add_machine("mini")
        _, workload = w.make(name="demo")
        base = f"/api/machines/mini/workloads/{workload}"
        foreign = {"Host": "evil.example", "X-CSRF-Token": w.operator.csrf()}
        expect(w.operator.request("POST", base + "/stop", headers=foreign).status == 403 and w.operator.request("POST", "/api/workloads", {}, headers=foreign).status == 403, "a foreign Host got through")
        expect(w.operator.request("POST", base + "/stop").status == 403 and w.operator.request("POST", "/api/workloads", {"name": "x"}).status == 403, "CSRF is not required")
        for path in ("/api/machines/mini/workloads/w-nope/stop", "/api/machines/ghost/workloads/w-1/stop", "/api/machines/mini/workloads/..%2Fx/stop", "/api/machines/mini/workloads/UPPER/delete"):
            reply = w.operator.write("POST", path, {"confirm": True})
            expect(reply.status in (400, 404), f"{path} gave {reply.status}")
        bad = [{"name": "Bad Name"}, {"kind": "metal"}, {"cpu": 0}, {"ram_mb": 100}, {"disk_gb": 0}, {"image": "--privileged"}, {"gpu_mode": "all"}, {"x": 1}]
        for change in bad:
            expect(w.create(**change).status == 400, f"accepted {change}")


def check_an_unreachable_agent_fails_the_command_cleanly():
    with world() as w:
        mini = w.add_machine("mini")
        mini.stop_agent()
        reply = w.create(name="lost")
        expect(reply.status == 502 and reply.body["error"]["code"] == "machine_unreachable", f"{reply.status} {reply.body}")
        failed = w.operator.request("GET", "/api/commands").body["commands"][0]
        expect(failed["state"] == "failed" and "reached" in failed["result"]["error"], f"command: {failed}")
        mini.start_agent()
        wait_for(lambda: w.view("mini")["state"] == "online", 20, "the machine did not come back")
        expect(w.create(name="again").status == 202, "the failed request still holds room")


def check_a_mixed_fleet_of_swift_and_rust_agents_gets_each_workload_where_it_can_run():
    with world() as w:
        w.add_machine("mac", engine="apple")
        w.add_machine("linux", engine="incus", flavor="rust")
        machine, container_id = w.make(name="box", kind="container")
        expect(machine == "linux", f"a container went to {machine}; the Mac cannot run one")
        done = w.wait_command(w.operator.write("POST", f"/api/machines/linux/workloads/{container_id}/delete", {"confirm": True}).body["command"]["id"])
        expect(os.path.getsize(os.path.join(w.machines["linux"].container.backups, done["result"]["backup_id"])) > 0, "no backup from the Linux machine")
        wait_for(lambda: w.view("linux")["workloads"] == [], 15, "the Linux machine still lists the deleted workload")
        expect(w.view("linux")["os"] in ("linux", "macos") and w.view("mac")["os"] == "macos", "the machine kinds did not reach the Root")
        reply = w.create(name="vmbox", kind="vm")
        expect(reply.status == 202 and reply.body["command"]["machine"] == "mac", f"a VM request went to {reply.body}")


def check_the_root_never_calls_an_address_outside_the_private_network():
    with world() as w:
        mini = w.add_machine("mini")
        mini.stop_agent()
        w.database().execute("UPDATE machines SET ip = '203.0.113.5' WHERE id = 'mini'").connection.commit()
        started = time.time()
        reply = w.create(name="nowhere")
        expect(reply.status == 502 and time.time() - started < 5, f"{reply.status} after {time.time() - started:.1f}s (a call to a public address would hang for the full timeout)")


def check_the_root_keeps_following_a_command_across_its_own_restart():
    container = FakeContainerWorld(FAKE_CONTAINER_RUN_DELAY="3")
    with world() as w:
        w.add_machine("mini", engine="apple", container=container)
        reply = w.create(name="slow")
        expect(reply.status == 202, f"create gave {reply.status}")
        command_id = reply.body["command"]["id"]
        w.root.stop()
        w.root.start()
        w.operator = Browser(w.root)
        done = w.wait_command(command_id, seconds=40)
        expect(done["result"]["workload_id"], "the command finished without a result")


def check_secrets_are_kept_apart_and_the_agent_takes_only_its_command_token():
    with world() as w:
        mini = w.add_machine("mini")
        raw = b"".join(open(os.path.join(w.root.dir, name), "rb").read() for name in os.listdir(w.root.dir) if name.startswith("root.sqlite3"))
        expect(mini.command_token.encode() not in raw and mini.machine_token.encode() not in raw, "a machine secret is in the Root's database in clear")
        sealed = w.database().execute("SELECT command_token_sealed FROM machines WHERE id = 'mini'").fetchone()[0]
        expect(sealed and mini.command_token not in sealed, "the command token is not sealed")
        expect(stat.S_IMODE(os.stat(os.path.join(w.root.dir, "root.key")).st_mode) == 0o600, "the Root's key file is not mode 600")
        expect(mini.agent.call("GET", "/v1/health", token=mini.machine_token)[0] == 401, "the Agent accepted the machine token for commands")
        expect(mini.agent.call("GET", "/v1/health")[0] == 200, "the Agent refused its command token")
        heartbeat = Browser(w.root).request("POST", "/v1/agents/heartbeat", {}, headers={"Authorization": f"Bearer {mini.command_token}"}, origin=None)
        expect(heartbeat.status == 401, "the Root accepted the command token as a machine token")


def check_commands_can_be_listed_and_read():
    with world() as w:
        w.add_machine("mini")
        w.make(name="one")
        w.make(name="two")
        listed = w.operator.request("GET", "/api/commands?limit=1").body["commands"]
        expect(len(listed) == 1 and listed[0]["params"]["name"] == "two", f"newest first: {listed}")
        expect(w.operator.request("GET", f"/api/commands/{listed[0]['id']}").status == 200, "a command cannot be read")
        for path in ("/api/commands/rc-nope", "/api/commands/..%2Fx", "/api/commands/UPPER"):
            expect(w.operator.request("GET", path).status == 404, f"{path} was not a 404")
        expect(Browser(w.root).request("GET", "/api/commands", headers={"Host": "evil.example"}).status == 403, "commands are readable for a foreign Host")


CHECKS = [
    check_a_request_through_the_root_creates_a_workload_on_the_machine, check_placement_takes_the_machine_with_the_most_room_and_honors_a_choice,
    check_the_root_refuses_what_fits_nowhere_and_says_why, check_two_requests_in_a_row_cannot_take_the_same_room,
    check_a_stale_view_is_corrected_by_the_agents_own_check, check_start_stop_and_a_confirmed_delete_with_a_backup,
    check_a_mixed_fleet_of_swift_and_rust_agents_gets_each_workload_where_it_can_run, check_actions_need_the_host_csrf_and_a_known_workload, check_an_unreachable_agent_fails_the_command_cleanly, check_the_root_never_calls_an_address_outside_the_private_network,
    check_the_root_keeps_following_a_command_across_its_own_restart, check_secrets_are_kept_apart_and_the_agent_takes_only_its_command_token,
    check_commands_can_be_listed_and_read,
]
