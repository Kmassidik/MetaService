"""Chat bundle install and version reporting."""
from contract.tests.support import expect, expect_error, expect_schema

GOOD_SHA = "a" * 64


def _body(ctx, **overrides):
    body = {"command_id": ctx.new_id("c"), "version": "1.2.3", "sha256": GOOD_SHA}
    body.update(overrides)
    return body


def check_machine_install_shows_in_health(ctx):
    reply = ctx.post("/v1/bundle/install", _body(ctx, version="2.0.1"))
    expect(reply.status == 202, f"bundle install gave {reply.status}: {reply.body}")
    expect_schema("CommandAccepted", reply.body, "bundle install reply")
    ctx.wait_for(reply.body["command_id"])
    expect(ctx.get("/v1/health").body["bundle_version"] == "2.0.1", "health does not report the installed bundle version")


def check_workload_install_shows_on_the_workload(ctx):
    workload_id, _ = ctx.create_small()
    reply = ctx.post("/v1/bundle/install", _body(ctx, version="3.1.4", workload_id=workload_id))
    ctx.wait_for(reply.body["command_id"])
    listed = next(w for w in ctx.workloads() if w["id"] == workload_id)
    expect(listed["bundle_version"] == "3.1.4", f"the workload does not report the bundle: {listed}")
    ctx.delete(f"/v1/workloads/{workload_id}")


def check_install_is_idempotent(ctx):
    body = _body(ctx)
    first, second = ctx.post("/v1/bundle/install", body), ctx.post("/v1/bundle/install", body)
    expect(first.body["command_id"] == second.body["command_id"], "a repeated install got another command id")


def check_install_rejects_bad_input(ctx):
    bad = [{"version": "1.2"}, {"version": "v1.2.3"}, {"version": "1.2.3; reboot"}, {"sha256": "short"},
           {"sha256": "G" * 64}, {"workload_id": "Bad Id"}, {"surprise": 1}]
    for change in bad:
        expect_error(ctx.post("/v1/bundle/install", _body(ctx, **change)), 400, f"bundle with {change}")


def check_install_into_unknown_workload_is_404(ctx):
    reply = ctx.post("/v1/bundle/install", _body(ctx, workload_id=ctx.new_id("none")))
    expect_error(reply, 404, "install into a missing workload")


CHECKS = [
    check_machine_install_shows_in_health, check_workload_install_shows_on_the_workload,
    check_install_is_idempotent, check_install_rejects_bad_input, check_install_into_unknown_workload_is_404,
]
