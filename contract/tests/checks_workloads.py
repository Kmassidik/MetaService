"""Workload lifecycle, validation at the edge, space accounting, idempotency."""
from contract.tests.support import expect, expect_error, expect_schema

INJECTION_NAMES = [
    "UPPER", "has space", "semi;colon", "$(reboot)", "`id`", "a/b", "../etc", "-leading-dash", "",
    "x'; DROP TABLE workloads;--", "x\" OR \"1\"=\"1", "<script>alert(1)</script>", "a" * 64, "name\nnewline",
]


def _base(ctx, **overrides):
    body = {"command_id": ctx.new_id("c"), "name": ctx.new_id("w"), "kind": ctx.kind(), "cpu": 1, "ram_mb": 512, "disk_gb": 1}
    body.update(overrides)
    return body


def check_list_fits_schema(ctx):
    reply = ctx.get("/v1/workloads")
    expect(reply.status == 200, f"list gave {reply.status}")
    expect_schema("WorkloadList", reply.body, "workload list")


def check_create_flow(ctx):
    body = _base(ctx, cpu=2, ram_mb=1024, disk_gb=3)
    reply = ctx.post("/v1/workloads", body)
    expect(reply.status == 202, f"create gave {reply.status}: {reply.body}")
    expect_schema("CommandAccepted", reply.body, "create reply")
    done = ctx.wait_for(reply.body["command_id"])
    expect_schema("Command", done, "finished create command")
    found = [w for w in ctx.workloads() if w["id"] == done["workload_id"]]
    expect(len(found) == 1, "the new workload is not in the list")
    expect_schema("Workload", found[0], "listed workload")
    sizes = (found[0]["cpu"], found[0]["ram_mb"], found[0]["disk_gb"], found[0]["name"], found[0]["kind"])
    expect(sizes == (2, 1024, 3, body["name"], ctx.kind()), f"the workload does not match the request: {found[0]}")


def check_create_is_idempotent(ctx):
    body = _base(ctx)
    first = ctx.post("/v1/workloads", body)
    second = ctx.post("/v1/workloads", body)
    expect(first.status == 202 and second.status == 202, "a repeated create was not accepted")
    expect(first.body["command_id"] == second.body["command_id"], "a repeat got another command id")
    named = [w for w in ctx.workloads() if w["name"] == body["name"]]
    expect(len(named) == 1, f"a repeated create made {len(named)} workloads")


def check_create_rejects_bad_names(ctx):
    for name in INJECTION_NAMES:
        reply = ctx.post("/v1/workloads", _base(ctx, name=name))
        expect_error(reply, 400, f"name {name[:20]!r}")


def check_create_rejects_bad_numbers_and_shapes(ctx):
    bad = [
        {"cpu": 0}, {"cpu": 65}, {"cpu": "2"}, {"cpu": 1.5}, {"ram_mb": 511}, {"ram_mb": -1}, {"disk_gb": 0},
        {"disk_gb": -5}, {"disk_gb": 100001}, {"kind": "bare-metal"}, {"gpu_mode": "all"}, {"image": "Bad Image; rm"},
        {"command_id": "Has Space"}, {"command_id": "../x"}, {"surprise": "extra field"},
    ]
    for change in bad:
        expect_error(ctx.post("/v1/workloads", _base(ctx, **change)), 400, f"create with {change}")
    for field in ("command_id", "name", "kind", "cpu", "ram_mb", "disk_gb"):
        body = _base(ctx)
        del body[field]
        expect_error(ctx.post("/v1/workloads", body), 400, f"create without {field}")


def check_create_rejects_non_json(ctx):
    for raw in (b"not json", b"null", b"[]", b'"text"', b"{"):
        reply = ctx.client.request("POST", "/v1/workloads", raw=raw)
        expect_error(reply, 400, f"body {raw!r}")


def check_oversized_body_is_413(ctx):
    reply = ctx.client.request("POST", "/v1/workloads", raw=b"{" + b" " * (70 * 1024) + b"}")
    expect_error(reply, 413, "70 KB body")


def check_rejected_creates_leave_nothing_behind(ctx):
    before = {w["id"] for w in ctx.workloads()}
    ctx.post("/v1/workloads", _base(ctx, name="Bad Name"))
    ctx.post("/v1/workloads", _base(ctx, cpu=0))
    expect({w["id"] for w in ctx.workloads()} == before, "a rejected create left a workload behind")


def check_refusal_when_disk_is_short(ctx):
    free = ctx.facts()["free_disk_gb"]
    if free + 1 > 100000:
        return
    before = len(ctx.workloads())
    reply = ctx.post("/v1/workloads", _base(ctx, disk_gb=free + 1))
    expect(reply.status == 409, f"wanted 409 for too little disk, got {reply.status} {reply.body}")
    expect_schema("Refusal", reply.body, "disk refusal")
    detail = reply.body["error"]
    expect((detail["resource"], detail["needed"], detail["free"]) == ("disk_gb", free + 1, free), f"refusal numbers are wrong: {detail}")
    expect(len(ctx.workloads()) == before, "a refused create still made a workload")


def check_refusal_when_ram_is_short(ctx):
    free = ctx.facts()["free_ram_mb"]
    if free + 1 > 1048576:
        return
    reply = ctx.post("/v1/workloads", _base(ctx, ram_mb=max(free + 1, 512)))
    expect(reply.status == 409, f"wanted 409 for too little RAM, got {reply.status} {reply.body}")
    expect_schema("Refusal", reply.body, "ram refusal")
    expect(reply.body["error"]["resource"] == "ram_mb", "the refusal names the wrong resource")


def check_missing_capability_is_refused(ctx):
    caps = ctx.facts()["capabilities"]
    if not caps["gpu_in_vm"]:
        reply = ctx.post("/v1/workloads", _base(ctx, kind="vm", gpu_mode="passthrough"))
        expect(reply.status == 409 and reply.body["error"]["code"] == "missing_capability", f"vm gpu passthrough: {reply.status} {reply.body}")
    if not caps["gpu_in_container"]:
        reply = ctx.post("/v1/workloads", _base(ctx, kind="container", gpu_mode="container"))
        expect(reply.status == 409 and reply.body["error"]["code"] == "missing_capability", f"container gpu: {reply.status} {reply.body}")


def check_disk_is_counted_and_returned(ctx):
    before = ctx.facts()["free_disk_gb"]
    workload_id, _ = ctx.create_small(disk_gb=4)
    expect(ctx.facts()["free_disk_gb"] == before - 4, "free disk did not drop by the workload's disk")
    ctx.wait_for(ctx.delete(f"/v1/workloads/{workload_id}").body["command_id"])
    expect(ctx.facts()["free_disk_gb"] == before, "free disk did not come back after delete")


def check_ram_counts_only_while_running(ctx):
    before = ctx.facts()["free_ram_mb"]
    workload_id, _ = ctx.create_small(ram_mb=1024)
    expect(ctx.facts()["free_ram_mb"] == before - 1024, "free RAM did not drop for a running workload")
    ctx.post(f"/v1/workloads/{workload_id}/stop")
    expect(ctx.facts()["free_ram_mb"] == before, "a stopped workload still holds RAM")
    ctx.delete(f"/v1/workloads/{workload_id}")


def check_start_and_stop(ctx):
    workload_id, _ = ctx.create_small()
    stopped = ctx.post(f"/v1/workloads/{workload_id}/stop")
    expect(stopped.status == 202, f"stop gave {stopped.status}")
    ctx.wait_for(stopped.body["command_id"])
    expect(_state(ctx, workload_id) == "stopped", "the workload is not stopped")
    started = ctx.post(f"/v1/workloads/{workload_id}/start")
    ctx.wait_for(started.body["command_id"])
    expect(_state(ctx, workload_id) == "running", "the workload is not running")
    ctx.delete(f"/v1/workloads/{workload_id}")


def check_command_id_makes_stop_safe_to_repeat(ctx):
    workload_id, _ = ctx.create_small()
    headers = {"X-Command-Id": ctx.new_id("c")}
    first = ctx.post(f"/v1/workloads/{workload_id}/stop", headers=headers)
    second = ctx.post(f"/v1/workloads/{workload_id}/stop", headers=headers)
    expect(first.body["command_id"] == second.body["command_id"], "a repeated stop got another command id")
    bad = ctx.post(f"/v1/workloads/{workload_id}/stop", headers={"X-Command-Id": "Bad Id"})
    expect_error(bad, 400, "bad X-Command-Id")
    ctx.delete(f"/v1/workloads/{workload_id}")


def check_delete_backs_up_first(ctx):
    workload_id, _ = ctx.create_small()
    reply = ctx.delete(f"/v1/workloads/{workload_id}")
    expect(reply.status == 202, f"delete gave {reply.status}")
    done = ctx.wait_for(reply.body["command_id"])
    expect(done["result"] and done["result"].get("backup_id"), f"delete did not report a backup: {done}")
    expect(workload_id not in {w["id"] for w in ctx.workloads()}, "the workload is still listed after delete")
    expect_error(ctx.delete(f"/v1/workloads/{workload_id}"), 404, "second delete")


def check_unknown_and_hostile_ids_are_404(ctx):
    paths = ["nope", "..%2Fetc%2Fpasswd", "UPPER", "a%00b", "x" * 80, "%24%28id%29"]
    for item in paths:
        for method, suffix in (("POST", "/start"), ("POST", "/stop"), ("DELETE", "")):
            reply = ctx.client.request(method, f"/v1/workloads/{item}{suffix}")
            expect_error(reply, 404, f"{method} id {item[:20]}")
    expect_error(ctx.get(f"/v1/commands/{ctx.new_id('none')}"), 404, "unknown command")


def _state(ctx, workload_id):
    return next(w["state"] for w in ctx.workloads() if w["id"] == workload_id)


CHECKS = [
    check_list_fits_schema, check_create_flow, check_create_is_idempotent, check_create_rejects_bad_names,
    check_create_rejects_bad_numbers_and_shapes, check_create_rejects_non_json, check_oversized_body_is_413,
    check_rejected_creates_leave_nothing_behind, check_refusal_when_disk_is_short, check_refusal_when_ram_is_short,
    check_missing_capability_is_refused, check_disk_is_counted_and_returned, check_ram_counts_only_while_running,
    check_start_and_stop, check_command_id_makes_stop_safe_to_repeat, check_delete_backs_up_first,
    check_unknown_and_hostile_ids_are_404,
]
