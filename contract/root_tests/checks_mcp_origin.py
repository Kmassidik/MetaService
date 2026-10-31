"""The creator record of every VM the parent makes (mcp/SPEC.md section 10.3), against a real Root and fake helpers: written for an MCP create and for a panel create,
sealed (and read as altered when the database was edited), refused edits and deletes, who deleted the VM, "unknown origin" for a VM the parent did not make, the short
`created_by` on the machine's workloads and in the MCP answers, and the one-time backfill of VMs that existed before the record did."""
import sqlite3
import time

from contract.root_tests.checks_monitor import enroll
from contract.root_tests.mcp_support import client_for, origin, parent, sql, wait_until, workload_of
from contract.root_tests.support import Browser, expect, running

PANEL_VM = {"name": "panel-box", "kind": "vm", "cpu": 1, "ram_mb": 2048, "disk_gb": 20, "machine": "mini"}


def panel_create(operator, machines, **changes):
    """A VM made from the panel; returns its id once the machine lists it."""
    reply = operator.write("POST", "/api/workloads", {**PANEL_VM, **changes})
    expect(reply.status == 202, f"panel create gave {reply.status}: {reply.raw[:200]!r}")
    command = reply.body["command"]["id"]
    done = wait_until(lambda: (lambda c: c if c["state"] == "succeeded" else None)(operator.request("GET", f"/api/commands/{command}").body["command"]), what="the panel create to finish")
    vm = done["result"]["workload_id"]
    wait_until(lambda: any(w["id"] == vm for w in operator.request("GET", "/api/machines/mini").body["workloads"]), what="the machine to list the VM")
    return vm


def check_origin_an_mcp_create_and_a_panel_create_each_leave_a_sealed_record():
    with parent() as (root, operator, machines):
        client, _, info = client_for(root, operator, "ayu", client_name="claude-code")
        vm = client.tool("create_vm", {"size": "small", "name": "from-ai"}).ok()["vm"]["id"]
        record = origin(operator, "mini", vm)
        expect(record["kind"] == "mcp" and record["actor"] == "mcp:ayu" and record["person_name"] == "ayu" and record["token_prefix"] == info["prefix"], record)
        expect(record["client"] == "claude-code 1.2.3" and record["source_ip"] == "127.0.0.1" and record["backfilled"] is False, record)
        expect(record["created_at"] and record["deleted_at"] is None and record["deleted_by"] is None and record["intact"] is True and len(record["fingerprint"]) == 8, record)
        short = workload_of(operator, "mini", vm)["created_by"]
        expect(short == {"kind": "mcp", "label": "ayu (MCP)", "fingerprint": record["fingerprint"], "intact": True}, short)
        panel_vm = panel_create(operator, machines)
        panel = origin(operator, "mini", panel_vm)
        expect(panel["kind"] == "panel" and panel["actor"] == "admin" and panel["person_name"] is None and panel["token_prefix"] is None and panel["client"] is None, panel)
        expect(panel["source_ip"] == "127.0.0.1" and panel["intact"] is True and panel["fingerprint"] != record["fingerprint"], panel)
        expect(workload_of(operator, "mini", panel_vm)["created_by"]["label"] == "panel (admin)", workload_of(operator, "mini", panel_vm))
        listed = {row["id"]: row for row in client.tool("list_vms").ok()["vms"]}
        expect(listed[vm]["created_by"]["label"] == "ayu (MCP)" and listed[vm]["created_by"]["fingerprint"] == record["fingerprint"], listed)
        expect(panel_vm not in listed, "the panel's VM is not this person's")
        expect(client.tool("vm_status", {"machine": "mini", "vm": vm}).ok()["created_by"] == short, "vm_status carries the same short form")


def check_origin_a_record_cannot_be_edited_and_an_altered_one_is_reported_as_altered():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "ayu")
        vm = client.tool("create_vm", {"size": "small"}).ok()["vm"]["id"]
        for statement in ("UPDATE vm_origin SET actor = 'mcp:mallory'", "UPDATE vm_origin SET seal = 'aaaaaaaaaaaaaaaa'", "DELETE FROM vm_origin"):
            try:
                sql(root, statement)
            except sqlite3.DatabaseError as error:
                expect("append only" in str(error), f"{statement}: {error}")
            else:
                raise AssertionError(f"the database accepted: {statement}")
        expect(origin(operator, "mini", vm)["intact"] is True, "refused edits change nothing")
        sql(root, "DROP TRIGGER vm_origin_only_deletion")
        sql(root, "UPDATE vm_origin SET person_name = 'mallory', actor = 'mcp:mallory' WHERE workload_id = ?", vm)
        altered = origin(operator, "mini", vm)
        expect(altered["intact"] is False and altered["person_name"] == "mallory", altered)
        expect(workload_of(operator, "mini", vm)["created_by"]["intact"] is False, "the machine's answer says altered too")
        expect(client.tool("vm_status", {"machine": "mini", "vm": vm}).ok()["created_by"]["intact"] is False, "and so does MCP")


def check_origin_a_delete_notes_who_deleted_through_mcp_and_through_the_panel():
    with parent() as (root, operator, machines):
        client, _, _ = client_for(root, operator, "ayu", scopes=["read", "create", "destroy"])
        mine = client.tool("create_vm", {"size": "small"}).ok()["vm"]["id"]
        theirs = panel_create(operator, machines)
        client.tool("delete_vm", {"machine": "mini", "vm": mine}).ok()
        wait_until(lambda: origin(operator, "mini", mine)["deleted_by"], what="the MCP delete to be noted")
        deleted = origin(operator, "mini", mine)
        expect(deleted["deleted_by"] == "mcp:ayu" and deleted["deleted_at"] and deleted["intact"] is True and deleted["created_at"], deleted)
        reply = operator.write("POST", f"/api/machines/mini/workloads/{theirs}/delete", {"confirm": True})
        expect(reply.status == 202, reply.raw)
        wait_until(lambda: origin(operator, "mini", theirs)["deleted_by"], what="the panel delete to be noted")
        expect(origin(operator, "mini", theirs)["deleted_by"] == "admin" and origin(operator, "mini", theirs)["kind"] == "panel", origin(operator, "mini", theirs))


def check_origin_a_vm_the_parent_did_not_make_shows_unknown_origin():
    with parent() as (root, operator, machines):
        machines["mini"].helper.make("old-one", kind="vm", gpu_mode="none")
        vm = machines["mini"].helper.engine.workloads()[0]["id"]
        wait_until(lambda: any(w["id"] == vm for w in operator.request("GET", "/api/machines/mini").body["workloads"]), what="the machine to list the VM")
        expect(origin(operator, "mini", vm) is None, "no record")
        expect(workload_of(operator, "mini", vm)["created_by"] == {"kind": "unknown", "label": "unknown origin", "fingerprint": None, "intact": True}, workload_of(operator, "mini", vm))
        expect(operator.request("GET", "/api/machines/mini/workloads/nope/origin").body["origin"] is None, "an unknown id is null too")
        expect(Browser(root, auto_login=False).request("GET", f"/api/machines/mini/workloads/{vm}/origin").status == 401, "the record needs the panel session")


def insert_workload(root, machine, workload):
    sql(root, "INSERT INTO workloads (id, machine_id, name, kind, state, cpu, ram_mb, disk_gb, gpu_mode, updated_at) VALUES (?, ?, ?, 'vm', 'running', 1, 512, 1, 'none', ?)",
        workload, machine, workload, int(time.time()))


def check_origin_the_backfill_records_existing_vms_as_the_admins_once_and_never_again():
    with running() as root:
        operator = Browser(root)
        enroll(operator, "dgx")
        root.stop()
        for workload in ("vm-3e2d", "vm-0019"):
            insert_workload(root, "dgx", workload)
        sql(root, "DELETE FROM settings WHERE key = 'vm_origin_backfilled_at'")
        root.start()
        rows = sql(root, "SELECT machine_id, workload_id, kind, actor, backfilled, created_at, person_id, token_prefix FROM vm_origin ORDER BY workload_id")
        expect(rows == [("dgx", "vm-0019", "panel", "admin", 1, None, None, None), ("dgx", "vm-3e2d", "panel", "admin", 1, None, None, None)], rows)
        record = origin(operator, "dgx", "vm-3e2d")
        expect(record["backfilled"] is True and record["created_at"] is None and record["actor"] == "admin" and record["intact"] is True, record)
        short = workload_of(operator, "dgx", "vm-3e2d")["created_by"]
        expect(short["label"] == "admin (recorded afterwards)" and short["kind"] == "panel" and short["fingerprint"] == record["fingerprint"] and short["intact"] is True, short)
        root.stop()
        insert_workload(root, "dgx", "vm-later")
        root.start()
        expect(sql(root, "SELECT COUNT(*) FROM vm_origin") == [(2,)], "a second start adds none")
        expect(origin(operator, "dgx", "vm-later") is None, "a VM that appears afterwards stays unknown")
        expect(workload_of(operator, "dgx", "vm-later")["created_by"]["kind"] == "unknown", workload_of(operator, "dgx", "vm-later"))
        sql(root, "DROP TRIGGER vm_origin_only_deletion")
        sql(root, "UPDATE vm_origin SET backfilled = 0 WHERE workload_id = 'vm-3e2d'")
        expect(origin(operator, "dgx", "vm-3e2d")["intact"] is False, "dropping the backfilled mark breaks the seal")


def check_origin_a_root_with_no_vms_writes_the_backfill_guard_so_later_vms_stay_unknown():
    with running() as root:
        operator = Browser(root)
        enroll(operator, "dgx")
        expect(sql(root, "SELECT COUNT(*) FROM settings WHERE key = 'vm_origin_backfilled_at'") == [(1,)], "the guard is written at the first start")
        root.stop()
        insert_workload(root, "dgx", "vm-late")
        root.start()
        expect(sql(root, "SELECT COUNT(*) FROM vm_origin") == [(0,)], "nothing is backfilled after the first start")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
