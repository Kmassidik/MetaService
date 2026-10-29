"""Read-only external-service conformance. Lifecycle is exercised against the Fake Agent in Root tests, never against an operator's real containers."""
from contract.tests.support import expect, expect_error, expect_schema

UNKNOWN = "docker:" + "0" * 64


def _list(ctx):
    reply = ctx.get("/v1/external-services")
    expect(reply.status == 200, f"external-service discovery gave {reply.status}: {reply.body}")
    expect_schema("ExternalServiceList", reply.body, "external-service discovery")
    return reply.body


def check_external_discovery_is_schema_valid_and_separate_from_workloads(ctx):
    before = ctx.workloads()
    first = _list(ctx)
    second = _list(ctx)
    after = ctx.workloads()
    expect(before == after, "read-only discovery changed the managed workload list")
    managed = {item["id"] for item in after}
    expect(all(item["id"] not in managed for item in first["services"]), "an external id was adopted as a managed workload")
    expect({item["id"] for item in first["services"]} == {item["id"] for item in second["services"]}, "two discoveries returned different ids without a lifecycle call")


def check_unknown_external_targets_are_404_and_have_no_delete(ctx):
    before = _list(ctx)
    for action in ("start", "stop", "restart"):
        expect_error(ctx.post(f"/v1/external-services/{UNKNOWN}/{action}"), 404, f"unknown external {action}")
    expect(ctx.delete(f"/v1/external-services/{UNKNOWN}").status in (404, 405), "external services must not have a delete route")
    expect(_list(ctx)["services"] == before["services"], "refused lifecycle calls changed external services")


CHECKS = [check_external_discovery_is_schema_valid_and_separate_from_workloads, check_unknown_external_targets_are_404_and_have_no_delete]
