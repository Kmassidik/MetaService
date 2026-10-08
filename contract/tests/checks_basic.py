"""Auth, headers, read-only endpoints, and error shapes."""
from contract import spec
from contract.tests.support import expect, expect_error, expect_schema

ENDPOINTS_NEEDING_TOKEN = [
    ("GET", "/v1/health"), ("GET", "/v1/facts"), ("GET", "/v1/workloads"),
    ("POST", "/v1/workloads"), ("POST", "/v1/bundle/install"), ("GET", "/v1/commands/abc"),
    ("POST", "/v1/workloads/abc/start"), ("POST", "/v1/workloads/abc/stop"), ("DELETE", "/v1/workloads/abc"),
]
WRONG_TOKENS = ["", "wrong", "Bearer", "x" * 500]


def check_no_token_is_401_everywhere(ctx):
    for method, path in ENDPOINTS_NEEDING_TOKEN:
        reply = ctx.client.request(method, path, body={} if method == "POST" else None, token=None)
        expect_error(reply, 401, f"{method} {path} without token")


def check_wrong_token_is_401(ctx):
    for wrong in WRONG_TOKENS:
        reply = ctx.client.request("GET", "/v1/facts", token=wrong)
        expect_error(reply, 401, f"wrong token {wrong[:8]!r}")


def check_wrong_token_changes_nothing(ctx):
    before = ctx.workloads()
    body = {"command_id": ctx.new_id("c"), "name": ctx.new_id("w"), "kind": "container", "cpu": 1, "ram_mb": 512, "disk_gb": 1}
    ctx.post("/v1/workloads", body, token="wrong")
    expect(ctx.workloads() == before, "a request with the wrong token created something")


def check_contract_header_on_every_reply(ctx):
    replies = [ctx.get("/v1/health"), ctx.client.request("GET", "/v1/health", token=None), ctx.get("/v1/nope")]
    for reply in replies:
        expect(reply.headers.get(spec.CONTRACT_HEADER) == spec.CONTRACT_VERSION,
               f"status {reply.status} lacks the {spec.CONTRACT_HEADER} header")


def check_health(ctx):
    reply = ctx.get("/v1/health")
    expect(reply.status == 200, f"health gave {reply.status}")
    expect_schema("Health", reply.body, "health")
    expect(reply.body["contract_version"] == spec.CONTRACT_VERSION, "health reports another contract version")


def check_facts(ctx):
    reply = ctx.get("/v1/facts")
    expect(reply.status == 200, f"facts gave {reply.status}")
    facts = reply.body
    expect_schema("Facts", facts, "facts")
    expect(facts["free_ram_mb"] <= facts["ram_total_mb"], "free RAM is larger than total RAM")
    expect(facts["free_disk_gb"] <= facts["disk_total_gb"], "free disk is larger than total disk")


def check_unknown_path_is_404_json(ctx):
    expect_error(ctx.get("/v1/nope"), 404, "unknown path")
    expect_error(ctx.get("/"), 404, "root path")


def check_errors_never_leak_the_token(ctx):
    replies = [ctx.client.request("GET", "/v1/facts", token="secret-guess-123456"), ctx.get("/v1/nope")]
    for reply in replies:
        expect(ctx.client.token.encode() not in reply.raw, "an error reply contains the real token")
        expect(b"secret-guess-123456" not in reply.raw, "an error reply echoes the supplied token")
        expect(b"Traceback" not in reply.raw, "an error reply shows a stack trace")


CHECKS = [
    check_no_token_is_401_everywhere, check_wrong_token_is_401, check_wrong_token_changes_nothing,
    check_contract_header_on_every_reply, check_health, check_facts, check_unknown_path_is_404_json,
    check_errors_never_leak_the_token,
]
