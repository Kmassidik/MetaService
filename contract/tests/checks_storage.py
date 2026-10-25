"""The storage map: GET /v1/storage and POST /v1/storage/scan (optional: a helper without them answers 404 to both, and passes)."""
import time

from contract.tests.support import expect, expect_error, expect_schema

SCAN_WAIT_SECONDS = 600
POLL_SECONDS = 0.5


def _served(ctx):
    reply = ctx.get("/v1/storage")
    if reply.status == 404:
        expect_error(ctx.post("/v1/storage/scan"), 404, "a helper without GET /v1/storage still has POST /v1/storage/scan")
        return None
    return reply


def check_storage_needs_the_token(ctx):
    for method in ("GET", "POST"):
        path = "/v1/storage" if method == "GET" else "/v1/storage/scan"
        expect_error(ctx.client.request(method, path, token=None), 401, f"{method} {path} without token")


def check_storage_read_fits_and_never_starts_a_scan(ctx):
    reply = _served(ctx)
    if reply is None:
        return
    expect(reply.status == 200, f"GET /v1/storage gave {reply.status}")
    expect_schema("Storage", reply.body, "storage")
    expect((reply.body["progress"] is None) == (not reply.body["scanning"]), "progress must be there exactly while a scan runs")


def _finished(ctx):
    deadline = time.time() + SCAN_WAIT_SECONDS
    while time.time() < deadline:
        body = ctx.get("/v1/storage").body
        if not body["scanning"] and body["map"] is not None:
            return body
        time.sleep(POLL_SECONDS)
    raise AssertionError("no map after the scan")


def check_a_scan_ends_in_a_map_the_panel_can_draw(ctx):
    if _served(ctx) is None:
        return
    started = ctx.post("/v1/storage/scan")
    expect(started.status == 202, f"POST /v1/storage/scan gave {started.status}")
    expect_schema("Storage", started.body, "scan")
    body = _finished(ctx)
    expect_schema("Storage", body, "storage after the scan")
    nodes = body["map"]["nodes"]
    expect(nodes[0]["parent"] == -1 and nodes[0]["type"] == "dir", "the first node is not the scanned folder")
    sums = [0] * len(nodes)
    for place, node in enumerate(nodes[1:], start=1):
        parent = node["parent"]
        expect(0 <= parent < place, f"node {place} points at {parent}, not an earlier node")
        expect(nodes[parent]["type"] == "dir", f"node {place} sits in a {nodes[parent]['type']}")
        expect(node["type"] == "dir" or node["parent"] != -1, "only the first node has no folder")
        sums[parent] += node["bytes"]
    for place, node in enumerate(nodes):
        expect(sums[place] <= node["bytes"], f"{node['name'] or 'a rest'} holds more than it weighs")
    disk = body["map"]["disk"]
    expect(disk["used_bytes"] + disk["free_bytes"] <= disk["total_bytes"], "used and free add up to more than the disk")


CHECKS = [check_storage_needs_the_token, check_storage_read_fits_and_never_starts_a_scan, check_a_scan_ends_in_a_map_the_panel_can_draw]
