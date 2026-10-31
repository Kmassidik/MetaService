"""The rules in front of the MCP tools, against a real Root and fake helpers: scopes, every quota with its message (counted per person, over all their tokens),
ownership between people, idempotency, disabling a person, the choice of a machine when none is named, the shared machine and the rate limits. There are no approvals:
every call that passes the checks runs at once."""
import threading

from agent.fake.engine import MachineSpec
from contract.root_tests.mcp_support import CARD, Client, client_for, make_person, make_token, parent, wait_until
from contract.root_tests.support import Browser, expect


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
        expect("approvals" not in " ".join(row["action"] for row in operator.request("GET", "/api/audit?limit=200").body["entries"]), "nothing waits for anybody")


def check_mcp_a_token_has_only_the_scopes_it_shares_with_its_person():
    with parent() as (root, operator, machines):
        person = make_person(operator, "Ayu", ["read", "create", "destroy"])
        narrow = Client(root, make_token(operator, person["id"], "narrow", scopes=["read", "create"])[0])
        wide = Client(root, make_token(operator, person["id"], "wide")[0])
        vm = wide.tool("create_vm", {"size": "small"}).ok()["vm"]["id"]
        expect('"destroy" scope' in narrow.tool("delete_vm", {"machine": "mini", "vm": vm}).error, "the narrow token cannot delete")
        operator.write("PATCH", f"/api/mcp/people/{person['id']}", {"scopes": ["read"]})
        expect('"create" scope' in wide.tool("create_vm", {"size": "small"}).error, "taking a scope from the person takes it from every token")
        expect(wide.tool("list_vms").ok()["vms"][0]["id"] == vm, "reads still work")


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
        expect(message == "gpu_memory_gb is capped at 4 for this person and 6 was asked for: ask for 4 or less.", message)
        expect(len(machines["mini"].helper.engine.workloads()) == 5, f"only the allowed creates ran: {len(machines['mini'].helper.engine.workloads())}")


def check_mcp_quotas_are_the_persons_and_count_over_all_their_tokens():
    with parent() as (root, operator, machines):
        person = make_person(operator, "Ayu", ["read", "create", "destroy"], {"max_vms": 2})
        first = Client(root, make_token(operator, person["id"], "laptop")[0])
        second = Client(root, make_token(operator, person["id"], "server")[0])
        one = first.tool("create_vm", {"size": "small"}).ok()["vm"]
        two = second.tool("create_vm", {"size": "small"}).ok()["vm"]
        expect(first.tool("create_vm", {"size": "small"}).error == "max_vms is 2 and 2 are alive: delete one first.", "a second token does not double the quota")
        expect(second.tool("create_vm", {"size": "small"}).error.startswith("max_vms is 2"), "from either token")
        expect({vm["id"] for vm in first.tool("list_vms").ok()["vms"]} == {one["id"], two["id"]}, "both tokens see both VMs")
        expect(second.tool("stop_vm", {"machine": "mini", "vm": one["id"]}).ok()["status"] == "done", "the second token changes the first token's VM")
        expect(first.tool("delete_vm", {"machine": "mini", "vm": two["id"]}).ok()["status"] in ("done", "deleting"), "and deletes one the other made")
        wait_until(lambda: first.tool("create_vm", {"size": "small"}).data.get("status") == "done", what="the freed slot to be usable by either token")
        listed = {row["name"]: row for row in operator.request("GET", "/api/mcp/people").body["people"]}
        expect(listed["Ayu"]["tokens"] == 2 and listed["Ayu"]["vms_alive"] == 2 and listed["Ayu"]["last_used_at"], listed)


def check_mcp_another_person_cannot_see_or_touch_a_persons_vms_or_the_operators():
    with parent() as (root, operator, machines):
        machines["mini"].helper.make("operators-box", kind="vm", gpu_mode="none")
        theirs = machines["mini"].helper.engine.workloads()[0]["id"]
        a, _, _ = client_for(root, operator, "alice", scopes=["read", "create", "destroy"])
        b, _, _ = client_for(root, operator, "bob", scopes=["read", "create", "destroy"])
        made = a.tool("create_vm", {"size": "small", "name": "alice-box"}).ok()
        mine = made["vm"]["id"]
        listed = b.tool("list_vms").ok()
        expect(listed["vms"] == [] and listed["others"] == 2, listed)
        for name in ("vm_status", "stop_vm", "start_vm", "delete_vm"):
            for vm in (mine, theirs):
                expect(b.tool(name, {"machine": "mini", "vm": vm}).error.startswith("There is no such VM for this person"), f"{name} on {vm}")
        states = {w["id"]: w["state"] for w in machines["mini"].helper.engine.workloads()}
        expect(states == {theirs: "running", mine: "running"}, states)
        expect(a.tool("vm_status", {"machine": "mini", "vm": mine}).ok()["name"] == "alice-box", "the owner still sees it")
        expect(b.tool("get_request", {"request_id": made["request_id"]}).error.startswith("There is no such request"), "and bob cannot read alice's requests")


def check_mcp_disabling_a_person_makes_every_token_401_and_the_vms_stay():
    with parent() as (root, operator, machines):
        person = make_person(operator, "Ayu", ["read", "create", "destroy"])
        one = Client(root, make_token(operator, person["id"], "laptop")[0])
        two = Client(root, make_token(operator, person["id"], "server")[0])
        vm = one.tool("create_vm", {"size": "small"}).ok()["vm"]
        disabled = operator.write("POST", f"/api/mcp/people/{person['id']}/disable")
        expect(disabled.status == 200 and disabled.body["person"]["disabled_at"], disabled.raw)
        for client in (one, two):
            reply = client.rpc("ping")
            expect(reply.status == 401 and reply.header("WWW-Authenticate") == 'Bearer realm="metaservice"', f"{reply.status}")
        expect(len(machines["mini"].helper.engine.workloads()) == 1, "the VM stays")
        expect(operator.write("POST", "/api/mcp/tokens", {"name": "more", "person_id": person["id"]}).status == 409, "no new token for a disabled person")
        expect(origin_kept(operator, vm["id"]), "and keeps its creator record")
        operator.write("POST", f"/api/mcp/people/{person['id']}/enable")
        expect(one.tool("list_vms").ok()["vms"][0]["id"] == vm["id"], "enabling brings the tokens and the VM back")


def origin_kept(operator, vm):
    return operator.request("GET", f"/api/machines/mini/workloads/{vm}/origin").body["origin"]["person_name"] == "Ayu"


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
        expect(len(client.tool("list_vms").ok()["vms"]) == 2, "two VMs")


def check_mcp_large_gpu_and_delete_run_at_once_with_no_approval_anywhere():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "direct", scopes=["read", "create", "destroy"], quotas={"max_vms": 1})
        made = client.tool("create_vm", {"size": "large", "name": "big-one", "machine": "mini"}).ok()
        expect(made["status"] == "done" and made["vm"]["vcpu"] == 4 and made["vm"]["name"] == "big-one", made)
        expect("needs_approval" not in str(made), made)
        deleted = client.tool("delete_vm", {"machine": "mini", "vm": made["vm"]["id"]}).ok()
        expect(deleted["status"] in ("done", "deleting"), deleted)
        wait_until(lambda: machines["mini"].helper.engine.workloads() == [], what="the VM to be deleted")
        wait_until(lambda: client.tool("create_vm", {"size": "small"}).data.get("status") == "done", what="the deleted VM to free the slot of max_vms 1")
        for path in ("/api/mcp/approvals", "/api/mcp/approvals/mr-x/approve"):
            expect(operator.request("GET", path).status == 404 or operator.write("POST", path).status == 404, f"{path} must be gone")


def check_mcp_without_a_machine_the_least_loaded_one_that_fits_is_chosen_or_a_plain_reason_is_given():
    big, small = MachineSpec(), MachineSpec(ram_total_mb=16384, disk_total_gb=400)
    with parent([("big", big, False), ("small", small, False)]) as (root, operator, machines):
        client, _, _ = client_for(root, operator, "chooser", quotas={"max_vms": 10, "max_ram_mb": 200000})
        first = client.tool("create_vm", {"size": "medium"}).ok()["vm"]
        expect(first["machine"] == "big", f"the roomier machine first: {first['machine']}")
        named = client.tool("create_vm", {"size": "small", "machine": "small"}).ok()["vm"]
        expect(named["machine"] == "small", "a named machine is respected")
        refused = client.tool("create_vm", {"size": "custom", "vcpu": 2, "ram_mb": 90000, "disk_gb": 10}).error
        expect("not enough RAM" in refused and "90000 needed" in refused, refused)
        expect(len([m for machine in machines.values() for m in machine.helper.engine.workloads()]) == 2, "a refused choice makes nothing")
        capacity = client.tool("machine_capacity", {"machine": "small"}).ok()
        expect(capacity["free_ram_mb"] < 8192 and "large" not in capacity["sizes_that_fit"], capacity)


def check_mcp_a_shared_machine_is_hidden_without_the_shared_scope_and_named_with_it():
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
        # The pretend helper listens on loopback, not at the Share a PC address, so the order cannot reach it: the call must say so plainly and keep no slot.
        refused = sharing.tool("create_vm", {"size": "small", "machine": "pc-in-berlin"})
        expect(refused.is_error and "could not be reached" in refused.error, refused.data)
        expect(sharing.tool("list_vms").ok()["vms"] == [], "a failed create holds no slot")


def check_mcp_a_gpu_limit_needs_the_scope_and_fits_the_card():
    card = MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True)
    with parent([("gpu-box", card, False)]) as (root, operator, machines):
        client, _, _ = client_for(root, operator, "gpu-user", scopes=["read", "create", "gpu"], quotas={"gpu_memory_gb": 16})
        listed = client.tool("list_machines").ok()["machines"][0]
        expect(listed["gpu"] == {"name": "NVIDIA GeForce RTX 5090", "total_gb": 32, "free_gb": 32}, listed)
        expect(client.tool("machine_capacity", {"machine": "gpu-box"}).ok()["gpu_free_gb"] == 32, "gpu_free_gb")
        done = client.tool("create_vm", {"size": "small", "gpu_memory_gb": 4}).ok()
        expect(done["status"] == "done" and done["vm"]["gpu_memory_gb"] == 4, done)
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


def check_mcp_requests_and_creates_are_rate_limited():
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
