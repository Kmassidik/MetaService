"""The rules in front of the MCP tools, against a real Root and fake helpers: scopes, every quota with its message, ownership between tokens, idempotency,
the approval round trip (approve, deny, expiry, a revoked token, auto_approve), the choice of a machine when none is named, the shared machine and the rate limits."""
import threading

from agent.fake.engine import MachineSpec
from contract.root_tests.mcp_support import CARD, client_for, parent, sql, wait_until
from contract.root_tests.support import Browser, expect

NEEDS_YOU = "A person must approve this in the panel (Settings, AI access)."


def approvals(operator):
    return operator.request("GET", "/api/mcp/approvals").body


def check_mcp_a_missing_scope_is_refused_in_words_and_changes_nothing():
    with parent() as (root, operator, machines):
        reader, _, _ = client_for(root, operator, "reader", scopes=["read"])
        creator, _, _ = client_for(root, operator, "creator", scopes=["read", "create"])
        refused = reader.tool("create_vm", {"size": "small"}).error
        expect('"create" scope' in refused and "Settings, AI access" in refused, refused)
        made = creator.tool("create_vm", {"size": "small"}).ok()["vm"]
        expect('"destroy" scope' in creator.tool("delete_vm", {"machine": "mini", "vm": made["id"]}).error, "delete needs destroy")
        expect('"gpu" scope' in creator.tool("create_vm", {"size": "small", "gpu_memory_gb": 4}).error, "a GPU limit needs gpu")
        expect('"read" scope' in client_for(root, operator, "nothing", scopes=["create"])[0].tool("list_vms").error, "reads need read")
        expect(len(machines["mini"].helper.engine.workloads()) == 1, "a refused call must not have made or removed anything")
        expect(not approvals(operator)["pending"], "a scope refusal waits for nobody")


def check_mcp_every_quota_refuses_with_the_limit_what_is_used_and_what_is_left():
    with parent() as (root, operator, machines):
        few, _, _ = client_for(root, operator, "few", quotas={"max_vms": 2})
        few.tool("create_vm", {"size": "small"}).ok()
        few.tool("create_vm", {"size": "small"}).ok()
        expect(few.tool("create_vm", {"size": "small"}).error == "max_vms is 2 and 2 are alive: delete one first.", "max_vms")
        cpu, _, _ = client_for(root, operator, "cpu", quotas={"max_vcpu": 3})
        cpu.tool("create_vm", {"size": "custom", "vcpu": 2, "ram_mb": 1024, "disk_gb": 5}).ok()
        message = cpu.tool("create_vm", {"size": "custom", "vcpu": 2, "ram_mb": 1024, "disk_gb": 5}).error
        expect(message.startswith("max_vcpu is 3 and 2 are in use: this VM needs 2 and only 1 is left."), message)
        ram, _, _ = client_for(root, operator, "ram", quotas={"max_ram_mb": 2048})
        message = ram.tool("create_vm", {"size": "custom", "vcpu": 1, "ram_mb": 4096, "disk_gb": 5}).error
        expect(message.startswith("max_ram_mb is 2048 and 0 are in use: this VM needs 4096 and only 2048 is left."), message)
        disk, _, _ = client_for(root, operator, "disk", quotas={"max_disk_gb": 30})
        disk.tool("create_vm", {"size": "small"}).ok()
        message = disk.tool("create_vm", {"size": "small"}).error
        expect(message.startswith("max_disk_gb is 30 and 20 are in use: this VM needs 20 and only 10 is left."), message)
        daily, _, _ = client_for(root, operator, "daily", quotas={"creates_per_day": 1, "max_vms": 5})
        daily.tool("create_vm", {"size": "small"}).ok()
        message = daily.tool("create_vm", {"size": "small"}).error
        expect(message == "creates_per_day is 1 and 1 were made in the last 24 hours: try again later.", message)
        gpu, _, _ = client_for(root, operator, "gpu", scopes=["read", "create", "gpu"], quotas={"gpu_memory_gb": 4})
        message = gpu.tool("create_vm", {"size": "small", "gpu_memory_gb": 6}).error
        expect(message == "gpu_memory_gb is capped at 4 for this token and 6 was asked for: ask for 4 or less.", message)
        expect(len(machines["mini"].helper.engine.workloads()) == 5, f"only the allowed creates ran: {len(machines['mini'].helper.engine.workloads())}")


def check_mcp_a_token_cannot_see_or_touch_another_tokens_vms_or_the_operators():
    with parent() as (root, operator, machines):
        machines["mini"].helper.make("operators-box", kind="vm", gpu_mode="none")
        theirs = machines["mini"].helper.engine.workloads()[0]["id"]
        a, _, _ = client_for(root, operator, "alice", scopes=["read", "create", "destroy"])
        b, _, _ = client_for(root, operator, "bob", scopes=["read", "create", "destroy"])
        mine = a.tool("create_vm", {"size": "small", "name": "alice-box"}).ok()["vm"]["id"]
        listed = b.tool("list_vms").ok()
        expect(listed["vms"] == [] and listed["others"] == 2, listed)
        for name in ("vm_status", "stop_vm", "start_vm", "delete_vm"):
            for vm in (mine, theirs):
                expect(b.tool(name, {"machine": "mini", "vm": vm}).error.startswith("There is no such VM for this token"), f"{name} on {vm}")
        expect(not approvals(operator)["pending"], "a refusal by ownership must not even wait for approval")
        states = {w["id"]: w["state"] for w in machines["mini"].helper.engine.workloads()}
        expect(states == {theirs: "running", mine: "running"}, states)
        expect(a.tool("vm_status", {"machine": "mini", "vm": mine}).ok()["name"] == "alice-box", "the owner still sees it")


def check_mcp_the_same_idempotency_key_gives_the_same_vm_and_never_a_second_one():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator)
        one = client.tool("create_vm", {"size": "small", "idempotency_key": "job-1"}).ok()
        two = client.tool("create_vm", {"size": "small", "idempotency_key": "job-1"}).ok()
        expect(one["vm"]["id"] == two["vm"]["id"] and one["request_id"] == two["request_id"], f"{one} {two}")
        statuses = []
        racers = [threading.Thread(target=lambda: statuses.append(client.tool("create_vm", {"size": "small", "idempotency_key": "job-1", "wait_seconds": 0}).is_error)) for _ in range(4)]
        for racer in racers:
            racer.start()
        for racer in racers:
            racer.join()
        expect(statuses == [False] * 4, f"four repeats at once: {statuses}")
        expect(len(machines["mini"].helper.engine.workloads()) == 1, "one key, one VM")
        other = client.tool("create_vm", {"size": "small", "idempotency_key": "job-2"}).ok()
        expect(other["vm"]["id"] != one["vm"]["id"] and len(machines["mini"].helper.engine.workloads()) == 2, "another key is another VM")
        again = client.tool("create_vm", {"size": "small", "idempotency_key": "job-1", "wait_seconds": 0}).ok()
        expect(again["vm"]["id"] == one["vm"]["id"], "a repeat with another wait still gives the first VM")
        mine = client.tool("list_vms").ok()["vms"]
        expect(len(mine) == 2, mine)


def check_mcp_the_approval_round_trip_for_a_large_vm_then_a_deny_and_a_second_press():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "needs-yes")
        waiting = client.tool("create_vm", {"size": "large", "name": "big-one", "machine": "mini"}).ok()
        expect(waiting["status"] == "needs_approval" and waiting["message"] == NEEDS_YOU and waiting["request_id"], waiting)
        expect(machines["mini"].helper.engine.workloads() == [], "nothing runs before a person says yes")
        expect(client.tool("get_request", {"request_id": waiting["request_id"]}).ok()["status"] == "pending_approval", "get_request while waiting")
        pending = approvals(operator)["pending"]
        expect(len(pending) == 1 and pending[0]["token_name"] == "needs-yes" and pending[0]["kind"] == "create" and pending[0]["state"] == "pending_approval", pending)
        expect("size large: 4 CPU, 8192 MB RAM, 60 GB disk" in pending[0]["description"] and pending[0]["params"]["machine"] == "mini", pending[0])
        expect("ssh_public_key" not in pending[0]["params"], "the panel does not need the key")
        approved = operator.write("POST", f"/api/mcp/approvals/{waiting['request_id']}/approve")
        expect(approved.status == 200 and approved.body["approval"]["state"] in ("running", "done") and approved.body["approval"]["decided_by"] == "admin", approved.raw)
        done = wait_until(lambda: (lambda r: r if r["status"] == "done" else None)(client.tool("get_request", {"request_id": waiting["request_id"]}).ok()), what="the approved create to finish")
        expect(done["vm"]["name"] == "big-one" and done["vm"]["vcpu"] == 4, done)
        again = operator.write("POST", f"/api/mcp/approvals/{waiting['request_id']}/approve")
        expect(again.status == 409 and again.body["error"]["code"] == "not_pending", again.raw)
        expect(operator.write("POST", f"/api/mcp/approvals/{waiting['request_id']}/deny").status == 409, "deny after approve")
        actors = [row["actor"] for row in operator.request("GET", "/api/audit?limit=100").body["entries"] if row["action"] == "workload.create"]
        expect(actors == ["mcp:needs-yes"], f"the stored action ran as the token: {actors}")
        second = client.tool("create_vm", {"size": "large"}).ok()["request_id"]
        denied = operator.write("POST", f"/api/mcp/approvals/{second}/deny")
        expect(denied.status == 200 and denied.body["approval"]["state"] == "denied", denied.raw)
        result = client.tool("get_request", {"request_id": second}).ok()
        expect(result["status"] == "denied" and "denied" in result["message"], result)
        expect(len(machines["mini"].helper.engine.workloads()) == 1, "a denied request runs nothing")
        recent = {row["id"]: row["state"] for row in approvals(operator)["recent"]}
        expect(recent[second] == "denied" and recent[waiting["request_id"]] in ("done", "running"), recent)
        no_session = Browser(root, auto_login=False).request("POST", f"/api/mcp/approvals/{second}/approve", {})
        expect(no_session.status in (401, 403), "a token or a stranger cannot approve")
        expect(client.rpc("tools/call", {"name": "approve", "arguments": {"request_id": second}}).body["error"]["code"] == -32602, "no tool approves")


def check_mcp_a_delete_waits_for_a_person_then_runs_and_frees_the_slot():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "deleter", scopes=["read", "create", "destroy"], quotas={"max_vms": 1})
        vm = client.tool("create_vm", {"size": "small"}).ok()["vm"]["id"]
        asked = client.tool("delete_vm", {"machine": "mini", "vm": vm}).ok()
        expect(asked["status"] == "needs_approval", asked)
        expect(len(machines["mini"].helper.engine.workloads()) == 1, "still there")
        pending = approvals(operator)["pending"][0]
        expect(pending["kind"] == "delete" and "Delete the VM" in pending["description"] and pending["params"]["vm"] == vm, pending)
        operator.write("POST", f"/api/mcp/approvals/{asked['request_id']}/approve")
        wait_until(lambda: machines["mini"].helper.engine.workloads() == [], what="the VM to be deleted")
        wait_until(lambda: client.tool("get_request", {"request_id": asked["request_id"]}).data.get("status") == "done", what="the delete request to be done")
        expect(client.tool("create_vm", {"size": "small"}).ok()["status"] == "done", "the deleted VM freed the slot of max_vms 1")


def check_mcp_auto_approve_skips_the_wait_and_a_revoked_token_or_an_old_request_cannot_be_approved():
    with parent() as (root, operator, machines):
        trusted, _, _ = client_for(root, operator, "trusted", scopes=["read", "create", "destroy"], auto_approve=True)
        made = trusted.tool("create_vm", {"size": "large"}).ok()
        expect(made["status"] == "done" and made["vm"]["vcpu"] == 4, made)
        deleted = trusted.tool("delete_vm", {"machine": "mini", "vm": made["vm"]["id"]}).ok()
        expect(deleted["status"] in ("done", "deleting"), deleted)
        expect(not approvals(operator)["pending"], "auto_approve never waits")
        careful, _, info = client_for(root, operator, "careful")
        waiting = careful.tool("create_vm", {"size": "large"}).ok()["request_id"]
        operator.write("DELETE", f"/api/mcp/tokens/{info['id']}")
        revoked = operator.write("POST", f"/api/mcp/approvals/{waiting}/approve")
        expect(revoked.status == 409 and revoked.body["error"]["code"] == "token_not_usable", revoked.raw)
        late, _, _ = client_for(root, operator, "late")
        old = late.tool("create_vm", {"size": "large"}).ok()["request_id"]
        sql(root, "UPDATE mcp_requests SET expires_at = 1 WHERE id = ?", old)
        expect(late.tool("get_request", {"request_id": old}).ok()["status"] == "expired", "pending requests expire")
        expired = operator.write("POST", f"/api/mcp/approvals/{old}/approve")
        expect(expired.status == 409 and expired.body["error"]["code"] == "not_pending", expired.raw)
        expect(all(row["id"] != old for row in approvals(operator)["pending"]), "an expired request leaves the waiting list")


def check_mcp_without_a_machine_the_least_loaded_one_that_fits_is_chosen_or_a_plain_reason_is_given():
    big, small = MachineSpec(), MachineSpec(ram_total_mb=16384, disk_total_gb=400)
    with parent([("big", big, False), ("small", small, False)]) as (root, operator, machines):
        client, _, _ = client_for(root, operator, "chooser", auto_approve=True, quotas={"max_vms": 10, "max_ram_mb": 200000})
        first = client.tool("create_vm", {"size": "medium"}).ok()["vm"]
        expect(first["machine"] == "big", f"the roomier machine first: {first['machine']}")
        named = client.tool("create_vm", {"size": "small", "machine": "small"}).ok()["vm"]
        expect(named["machine"] == "small", "a named machine is respected")
        refused = client.tool("create_vm", {"size": "custom", "vcpu": 2, "ram_mb": 90000, "disk_gb": 10}).error
        expect("not enough RAM" in refused and "90000 needed" in refused, refused)
        expect(len([m for m in machines.values() for _ in m.helper.engine.workloads()]) == 2, "a refused choice makes nothing")
        capacity = client.tool("machine_capacity", {"machine": "small"}).ok()
        expect(capacity["free_ram_mb"] < 8192 and "large" not in capacity["sizes_that_fit"], capacity)


def check_mcp_a_shared_machine_is_hidden_without_the_shared_scope_and_needs_approval_with_it():
    with parent([("home", MachineSpec(), False), ("pc-in-berlin", MachineSpec(ram_total_mb=262144), True)]) as (root, operator, machines):
        plain, _, _ = client_for(root, operator, "plain")
        names = [m["id"] for m in plain.tool("list_machines").ok()["machines"]]
        expect(names == ["home"], f"a shared machine is invisible: {names}")
        expect(plain.tool("machine_capacity", {"machine": "pc-in-berlin"}).error.startswith("There is no such machine"), "and refused by name")
        expect(plain.tool("create_vm", {"size": "small", "machine": "pc-in-berlin"}).error.startswith("There is no such machine"), "and cannot be created on")
        auto = plain.tool("create_vm", {"size": "small"}).ok()["vm"]
        expect(auto["machine"] == "home", "with no machine named a shared one is never chosen, even when it has the most room")
        sharing, _, _ = client_for(root, operator, "sharing", scopes=["read", "create", "shared"])
        listed = {m["id"]: m for m in sharing.tool("list_machines").ok()["machines"]}
        expect(listed["pc-in-berlin"]["shared"] is True and listed["home"]["shared"] is False, listed)
        asked = sharing.tool("create_vm", {"size": "small", "machine": "pc-in-berlin"}).ok()
        expect(asked["status"] == "needs_approval" and "shared machine" in asked["reason"], asked)
        pending = approvals(operator)["pending"][0]
        expect("on machine pc-in-berlin" in pending["description"] and pending["reason"] == "it runs on a shared machine", pending)
        # The pretend helper listens on loopback, not at the Share a PC address, so once approved the order cannot reach it: the request must say so plainly and free the slot.
        ended = operator.write("POST", f"/api/mcp/approvals/{asked['request_id']}/approve").body["approval"]
        expect(ended["state"] == "failed" and "could not be reached" in ended["message"], ended)
        expect(sharing.tool("get_request", {"request_id": asked["request_id"]}).ok()["status"] == "failed", "get_request says failed")
        expect(sharing.tool("list_vms").ok()["vms"] == [], "a failed approved create holds no slot")


def check_mcp_a_gpu_limit_needs_the_scope_a_person_and_fits_the_card():
    card = MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True)
    with parent([("gpu-box", card, False)]) as (root, operator, machines):
        client, _, _ = client_for(root, operator, "gpu-user", scopes=["read", "create", "gpu"], quotas={"gpu_memory_gb": 16})
        listed = client.tool("list_machines").ok()["machines"][0]
        expect(listed["gpu"] == {"name": "NVIDIA GeForce RTX 5090", "total_gb": 32, "free_gb": 32}, listed)
        expect(client.tool("machine_capacity", {"machine": "gpu-box"}).ok()["gpu_free_gb"] == 32, "gpu_free_gb")
        asked = client.tool("create_vm", {"size": "small", "gpu_memory_gb": 4}).ok()
        expect(asked["status"] == "needs_approval" and "GPU" in asked["reason"], asked)
        operator.write("POST", f"/api/mcp/approvals/{asked['request_id']}/approve")
        done = wait_until(lambda: (lambda r: r if r["status"] == "done" else None)(client.tool("get_request", {"request_id": asked["request_id"]}).ok()), what="the GPU create")
        expect(done["vm"]["gpu_memory_gb"] == 4, done)
        expect(machines["gpu-box"].helper.engine.created_requests[-1]["gpu_memory_gb"] == 4, "the helper was sent the limit")
        expect(client.tool("machine_capacity", {"machine": "gpu-box"}).ok()["gpu_free_gb"] == 28, "the booking shows")


def check_mcp_a_create_the_machine_refuses_frees_the_slot_and_says_why():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "unlucky", quotas={"max_vms": 1})
        machines["mini"].helper.engine.fail_creates_with("the disk is on fire")
        failed = client.tool("create_vm", {"size": "small", "idempotency_key": "k"})
        expect(failed.is_error and "the disk is on fire" in failed.error, failed.data)
        expect(client.tool("list_vms").ok()["vms"] == [], "the failed create holds no slot")
        machines["mini"].helper.engine.fail_creates_with(None)
        again = client.tool("create_vm", {"size": "small", "idempotency_key": "k2"}).ok()
        expect(again["status"] == "done", "the slot was free again")


def check_mcp_requests_and_creates_are_rate_limited_per_token():
    with parent() as (root, operator, machines):
        busy, _, _ = client_for(root, operator, "busy", quotas={"max_vms": 100, "creates_per_day": 1000, "max_ram_mb": 1000000, "max_vcpu": 200, "max_disk_gb": 5000})
        results = [busy.tool("create_vm", {"size": "custom", "vcpu": 1, "ram_mb": 512, "disk_gb": 1, "wait_seconds": 0}) for _ in range(11)]
        expect([r.is_error for r in results] == [False] * 10 + [True], [r.data for r in results][-2:])
        expect("10 creates in the last minute" in results[-1].error, results[-1].error)
        steady, _, _ = client_for(root, operator, "steady")
        statuses = [steady.rpc("ping").status for _ in range(62)]
        expect(statuses[:60] == [200] * 60 and statuses[60:] == [429, 429], statuses[55:])
        expect(client_for(root, operator, "other-token")[0].rpc("ping").status == 200, "the limit is per token")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
