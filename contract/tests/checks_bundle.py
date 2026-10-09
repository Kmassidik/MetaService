"""Chat bundle install and version reporting."""
from contract.tests.support import expect, expect_error, expect_schema


def _body(ctx, version=None, **overrides):
    version = version or ctx.bundle.versions[0]
    body = {"command_id": ctx.new_id("c"), "version": version, "sha256": ctx.bundle.sha[version]}
    body.update(overrides)
    return body


def _health_version(ctx):
    return ctx.get("/v1/health").body["bundle_version"]


def check_machine_install_shows_in_health(ctx):
    version = ctx.bundle.versions[1]
    reply = ctx.post("/v1/bundle/install", _body(ctx, version))
    expect(reply.status == 202, f"bundle install gave {reply.status}: {reply.body}")
    expect_schema("CommandAccepted", reply.body, "bundle install reply")
    ctx.wait_for(reply.body["command_id"])
    expect(_health_version(ctx) == version, "health does not report the installed bundle version")


def check_a_newer_bundle_replaces_an_older_one_and_the_older_can_come_back(ctx):
    first, second = ctx.bundle.versions[0], ctx.bundle.versions[1]
    for version in (first, second, first):
        ctx.wait_for(ctx.post("/v1/bundle/install", _body(ctx, version)).body["command_id"])
        expect(_health_version(ctx) == version, f"after installing {version}, health says {_health_version(ctx)}")


def check_the_install_result_names_the_version_and_port(ctx):
    done = ctx.wait_for(ctx.post("/v1/bundle/install", _body(ctx)).body["command_id"])
    expect(done["result"]["version"] == ctx.bundle.versions[0] and done["result"]["port"].isdigit(), f"result: {done['result']}")


def check_workload_install_shows_on_the_workload(ctx):
    workload_id, _ = ctx.create_small()
    version = ctx.bundle.versions[0]
    reply = ctx.post("/v1/bundle/install", _body(ctx, version, workload_id=workload_id))
    ctx.wait_for(reply.body["command_id"])
    listed = next(w for w in ctx.workloads() if w["id"] == workload_id)
    expect(listed["bundle_version"] == version, f"the workload does not report the bundle: {listed}")
    ctx.wait_for(ctx.delete(f"/v1/workloads/{workload_id}").body["command_id"])


def check_install_is_idempotent(ctx):
    body = _body(ctx)
    first, second = ctx.post("/v1/bundle/install", body), ctx.post("/v1/bundle/install", body)
    expect(first.body["command_id"] == second.body["command_id"], "a repeated install got another command id")


def check_a_wrong_checksum_installs_nothing(ctx):
    if not ctx.bundle.verifies:
        return
    before = _health_version(ctx)
    reply = ctx.post("/v1/bundle/install", _body(ctx, ctx.bundle.versions[1], sha256="b" * 64))
    done = ctx.wait_for(reply.body["command_id"], "failed")
    expect(done["state"] == "failed" and _health_version(ctx) == before, f"a wrong checksum changed the installed version: {before} -> {_health_version(ctx)}")


def check_install_rejects_bad_input(ctx):
    good = ctx.bundle.sha[ctx.bundle.versions[0]]
    bad = [{"version": "1.2"}, {"version": "v1.2.3"}, {"version": "1.2.3; reboot"}, {"sha256": "short"},
           {"sha256": "G" * 64}, {"workload_id": "Bad Id"}, {"surprise": 1}]
    for change in bad:
        expect_error(ctx.post("/v1/bundle/install", {"command_id": ctx.new_id("c"), "version": ctx.bundle.versions[0], "sha256": good, **change}), 400, f"bundle with {change}")


def check_install_into_unknown_workload_is_404(ctx):
    reply = ctx.post("/v1/bundle/install", _body(ctx, workload_id=ctx.new_id("none")))
    expect_error(reply, 404, "install into a missing workload")


CHECKS = [
    check_machine_install_shows_in_health, check_a_newer_bundle_replaces_an_older_one_and_the_older_can_come_back, check_the_install_result_names_the_version_and_port,
    check_workload_install_shows_on_the_workload, check_install_is_idempotent, check_a_wrong_checksum_installs_nothing, check_install_rejects_bad_input,
    check_install_into_unknown_workload_is_404,
]
