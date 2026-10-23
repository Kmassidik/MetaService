"""The GPU memory limit of a container (`gpu_memory_gb` on create, `gpu_memory_limit` in the facts). Refusals are checked on every helper; the checks that
make a limited container run only on a helper that announces `gpu_memory_limit`, because only that helper can cap and watch a card."""
from contract.tests.support import expect, expect_error, expect_schema

LIMIT_GB = 4
CONTAINER_WITH_GPU = {"kind": "container", "gpu_mode": "container"}


def _base(ctx, **overrides):
    body = {"command_id": ctx.new_id("c"), "name": ctx.new_id("w"), "kind": "container", "cpu": 1, "ram_mb": 512, "disk_gb": 1}
    body.update(overrides)
    return body


def _announces_the_limit(ctx):
    return ctx.facts().get("capabilities", {}).get("gpu_memory_limit") is True


def check_gpu_memory_limit_is_announced_as_a_boolean_equal_to_gpu_in_container(ctx):
    capabilities = ctx.facts().get("capabilities", {})
    if "gpu_memory_limit" not in capabilities:
        return
    expect(capabilities["gpu_memory_limit"] == capabilities["gpu_in_container"], f"gpu_memory_limit must equal gpu_in_container: {capabilities}")


def check_gpu_memory_limit_outside_one_to_1024_is_refused(ctx):
    for bad in (0, -1, 1025, 4.5, "4", True, None):
        expect_error(ctx.post("/v1/workloads", _base(ctx, **CONTAINER_WITH_GPU, gpu_memory_gb=bad)), 400, f"gpu_memory_gb {bad!r}")


def check_gpu_memory_limit_without_a_gpu_container_is_refused(ctx):
    for change in ({"kind": "vm"}, {"gpu_mode": "none"}, {"gpu_mode": "passthrough"}, {"kind": "vm", "gpu_mode": "container"}):
        body = _base(ctx, **{**CONTAINER_WITH_GPU, **change}, gpu_memory_gb=LIMIT_GB)
        expect_error(ctx.post("/v1/workloads", body), 400, f"gpu_memory_gb with {change}")


def check_a_container_with_a_gpu_memory_limit_reports_it(ctx):
    if not _announces_the_limit(ctx):
        return
    reply = ctx.post("/v1/workloads", _base(ctx, **CONTAINER_WITH_GPU, gpu_memory_gb=LIMIT_GB))
    expect(reply.status == 202, f"create with a limit gave {reply.status}: {reply.body}")
    done = ctx.wait_for(reply.body["command_id"])
    listed = [w for w in ctx.workloads() if w["id"] == done["workload_id"]]
    expect(len(listed) == 1 and listed[0]["gpu_memory_gb"] == LIMIT_GB, f"the limit is not reported: {listed}")
    expect_schema("Workload", listed[0], "a workload with a GPU memory limit")


def check_a_container_without_a_limit_reports_none(ctx):
    workload_id, _ = ctx.create_small()
    listed = [w for w in ctx.workloads() if w["id"] == workload_id][0]
    expect(listed.get("gpu_memory_gb") is None, f"no limit was asked for but {listed.get('gpu_memory_gb')} is reported")


def check_stopped_reason_may_carry_a_code_message_and_numbers(ctx):
    reason = {"code": "gpu_memory_over_limit", "message": "It used 5 GB; the limit is 4 GB.", "used_gb": 5.5, "limit_gb": 4}
    expect_schema("StoppedReason", reason, "a watchdog stopped_reason")
    expect_schema("StoppedReason", {"exit_code": 1, "log_tail": "x"}, "a stopped_reason from a VM that quit")


CHECKS = [check_gpu_memory_limit_is_announced_as_a_boolean_equal_to_gpu_in_container, check_gpu_memory_limit_outside_one_to_1024_is_refused,
          check_gpu_memory_limit_without_a_gpu_container_is_refused, check_a_container_with_a_gpu_memory_limit_reports_it,
          check_a_container_without_a_limit_reports_none, check_stopped_reason_may_carry_a_code_message_and_numbers]
