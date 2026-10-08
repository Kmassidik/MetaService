"""Scan: router and nmap sources, merging, limits, adding found devices. Uses fake nmap, arp and MikroTik programs."""
import json
import os
import pathlib
import tempfile
import time
from contextlib import contextmanager

from contract.root_tests.fakes.fake_router import PASSWORD, USER, make_router
from contract.root_tests.support import Browser, RunningRoot, expect, local_private_ip, running

FAKES = pathlib.Path(__file__).parent / "fakes"
AGENT_PORT = "9101"


class Skip(Exception):
    pass


@contextmanager
def scan_root(router_password=PASSWORD, with_router=True, nmap="fake", nmap_env=None, extra_env_lines=""):
    ip = local_private_ip()
    if ip is None:
        raise Skip("no private LAN address on this machine")
    prefix = ip.rsplit(".", 1)[0]
    log = tempfile.mktemp(prefix="ms-nmap-log-")
    server = make_router(ip, prefix) if with_router else None
    lines = ["ALLOWED_EMAILS=kurnia@example.com", f"SCAN_SUBNET={prefix}.0/24", f"ARP_PATH={FAKES / 'fake_arp.py'}"]
    lines.append(f"NMAP_PATH={FAKES / 'fake_nmap.py'}" if nmap == "fake" else "NMAP_PATH=/nonexistent/nmap")
    if with_router:
        lines += [f"ROUTER_URL=http://{ip}:{server.server_address[1]}", f"ROUTER_USER={USER}", f"ROUTER_PASSWORD={router_password}"]
    env = {"FAKE_NMAP_LOG": log, "FAKE_ARP_PREFIX": prefix, **(nmap_env or {})}
    root = RunningRoot(env_text="\n".join(lines + [extra_env_lines]) + "\n", process_env=env).start()
    root.scan_prefix, root.scan_log = prefix, log
    try:
        yield root
    finally:
        root.stop()
        if server:
            server.shutdown()


def start_and_wait(operator, wait=15, body=None):
    reply = operator.write("POST", "/api/scans", body)
    expect(reply.status == 202, f"starting a scan gave {reply.status}: {reply.raw[:150]!r}")
    deadline = time.time() + wait
    while time.time() < deadline:
        scan = operator.request("GET", "/api/scans/latest").body["scan"]
        if scan["state"] != "running":
            return scan
        time.sleep(0.1)
    raise AssertionError("the scan did not finish in time")


def by_ip(scan):
    return {row["ip"].rsplit(".", 1)[1]: row for row in scan["results"]}


def check_scan_setup_describes_what_is_available():
    with scan_root() as root:
        operator = Browser(root)
        expect(operator.request("GET", "/api/scan/setup").status == 401, "setup is open without a session")
        operator.sign_in()
        setup = operator.request("GET", "/api/scan/setup").body
        expect(setup == {"subnet": f"{root.scan_prefix}.0/24", "router_configured": True, "nmap_available": True}, f"setup: {setup}")


def check_a_scan_merges_router_nmap_and_arp():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["state"] == "done", f"scan state {scan['state']}")
        expect(scan["sources"] == {"router": "ok", "nmap": "ok", "agent_probe": "ok", "arp": "ok"}, f"sources: {scan['sources']}")
        found = by_ip(scan)
        expect(set(found) == {"1", "40", "50", "60", "66", "90"}, f"found {sorted(found)}")
        expect(found["1"]["hostname"] == "router.lan" and found["1"]["vendor"] == "MikroTik", f".1: {found['1']}")
        expect(set(found["1"]["seen_by"]) == {"router", "nmap", "arp"}, f".1 seen by {found['1']['seen_by']}")
        expect(found["50"]["seen_by"] == ["router"] and found["50"]["hostname"] == "printer", f".50: {found['50']}")
        expect(found["40"]["mac"] == "00:1A:2B:3C:4D:40", f"arp mac was not normalized: {found['40']['mac']}")
        expect(found["60"]["agent_port_open"] is True and found["40"]["agent_port_open"] is False, "agent port flags are wrong")
        expect(found["90"]["mac"] is None, "an incomplete ARP entry produced a MAC")
        expect(all(not row["ip"].startswith("10.99") for row in scan["results"]), "an address outside the subnet got in")


def check_hostile_device_names_are_cleaned():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        name = by_ip(start_and_wait(operator))["66"]["hostname"]
        expect("\x1b" not in name and len(name) <= 100, f"control characters survived: {name!r}")
        expect(name.startswith("<img"), "the name should be kept as plain text for the UI to escape")


def check_a_scan_only_targets_the_configured_subnet():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        start_and_wait(operator, body={"subnet": "8.8.8.0/24", "extra": "-iL /etc/passwd"})
        calls = [json.loads(line) for line in open(root.scan_log)]
        expect(calls and all("8.8.8.0/24" not in call and not any("passwd" in part for part in call) for call in calls), f"request data reached nmap: {calls}")
        sweep = next(call for call in calls if "-sn" in call)
        expect(sweep[-1] == f"{root.scan_prefix}.0/24", f"sweep target was {sweep[-1]}")
        probe = next(call for call in calls if "-p" in call)
        targets = probe[probe.index("-oX") + 2:]
        expect(targets and all(t.startswith(root.scan_prefix + ".") and not t.startswith("-") for t in targets), f"probe targets: {targets}")
        expect(probe[probe.index("-p") + 1] == AGENT_PORT, "probe port is not the Agent port")


def check_only_one_scan_runs_at_a_time():
    with scan_root(nmap_env={"FAKE_NMAP_DELAY": "1"}) as root:
        operator = Browser(root)
        operator.sign_in()
        first = operator.write("POST", "/api/scans")
        second = operator.write("POST", "/api/scans")
        expect((first.status, second.status) == (202, 409), f"got {(first.status, second.status)}")
        expect(second.body["error"]["code"] == "scan_running", "wrong refusal code")


def check_scans_need_a_session_and_csrf():
    with scan_root() as root:
        operator = Browser(root)
        expect(operator.request("POST", "/api/scans", {}).status == 401, "a scan started without a session")
        operator.sign_in()
        expect(operator.request("POST", "/api/scans", {}).status == 403, "a scan started without CSRF")
        expect(operator.request("GET", "/api/scans/latest").body == {"scan": None}, "latest should be null before any scan")
        expect(operator.request("GET", "/api/scans/99999").status == 404 and operator.request("GET", "/api/scans/abc").status == 404, "bad run ids should be 404")


def check_scans_are_rate_limited():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        codes = []
        for _ in range(8):
            codes.append(operator.write("POST", "/api/scans").status)
            time.sleep(0.4)
        expect(429 in codes[6:], f"no rate limit after six scans: {codes}")


def check_a_wrong_router_password_does_not_break_the_scan():
    with scan_root(router_password="wrong") as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["state"] == "done" and scan["sources"]["router"] == "refused_401", f"sources: {scan['sources']}")
        expect(by_ip(scan)["60"]["hostname"] is None, "router data appeared although the router refused")
        expect(b"wrong" not in operator.request("GET", "/api/scans/latest").raw, "the router password is in a reply")


def check_a_scan_works_without_a_router():
    with scan_root(with_router=False) as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["state"] == "done" and scan["sources"]["router"] == "not_configured", f"sources: {scan['sources']}")
        expect(operator.request("GET", "/api/scan/setup").body["router_configured"] is False, "setup says a router is configured")


def check_a_scan_works_without_nmap_and_fails_with_nothing():
    with scan_root(nmap="missing") as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["sources"]["nmap"] == "missing" and scan["state"] == "done" and "50" in by_ip(scan), f"router-only scan: {scan['sources']}")
    with scan_root(nmap="missing", with_router=False, extra_env_lines="ARP_PATH=/nonexistent/arp") as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["state"] == "failed", f"a scan with no working source should fail, got {scan['state']}")


def check_a_failing_nmap_is_reported_not_hidden():
    with scan_root(nmap_env={"FAKE_NMAP_FAIL": "1"}) as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        expect(scan["sources"]["nmap"] == "failed" and scan["sources"]["router"] == "ok", f"sources: {scan['sources']}")


def check_adding_found_devices_makes_pinned_tokens():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        found = by_ip(scan)
        reply = operator.write("POST", f"/api/scans/{scan['id']}/add", {"items": [{"result_id": found["50"]["id"], "name": "printer"}, {"result_id": found["60"]["id"], "name": "dgx-spark"}]})
        expect(reply.status == 201, f"add gave {reply.status}: {reply.raw[:150]!r}")
        invites = reply.body["invites"]
        expect([i["name"] for i in invites] == ["printer", "dgx-spark"] and all(len(i["enrollment_token"]) >= 43 for i in invites), f"invites: {invites}")
        expect(invites[0]["ip"] == found["50"]["ip"], "an invite is not pinned to the scanned address")
        agent = Browser(root)
        pinned = agent.request("POST", "/v1/agents/enroll", {"enrollment_token": invites[0]["enrollment_token"], "name": "printer"}, origin=None)
        expect(pinned.status == 401, f"a token pinned to {found['50']['ip']} worked from another address: {pinned.status}")
        audit = operator.request("GET", "/api/audit").body["entries"]
        expect(any(e["action"] == "enrollment.create" and "from_scan" in e["detail"] for e in audit), "adding from a scan was not audited")


def check_add_refuses_bad_requests():
    with scan_root() as root:
        operator = Browser(root)
        operator.sign_in()
        scan = start_and_wait(operator)
        rid = by_ip(scan)["50"]["id"]
        path = f"/api/scans/{scan['id']}/add"
        bad = [{"items": []}, {"items": [{"result_id": rid, "name": "Bad Name"}]}, {"items": [{"result_id": rid, "name": "a"}, {"result_id": rid, "name": "b"}]},
               {"items": [{"result_id": rid, "name": "a"}, {"result_id": by_ip(scan)["60"]["id"], "name": "a"}]}, {"items": [{"result_id": rid}]},
               {"items": [{"result_id": "1", "name": "a"}]}, {"items": [{"result_id": 1, "name": "a", "x": 1}]},
               {"items": [{"result_id": rid + i, "name": f"m{i}"} for i in range(51)]}, {"nope": 1}]
        for body in bad:
            expect(operator.write("POST", path, body).status == 400, f"accepted {str(body)[:80]}")
        expect(operator.write("POST", path, {"items": [{"result_id": 999999, "name": "x"}]}).status == 404, "an unknown result was accepted")
        expect(operator.write("POST", f"/api/scans/999999/add", {"items": [{"result_id": rid, "name": "x"}]}).status == 404, "an unknown run was accepted")
        expect(operator.request("POST", path, {"items": [{"result_id": rid, "name": "x"}]}).status == 403, "adding worked without CSRF")


def check_a_pinned_invite_works_only_from_its_address():
    with running() as root:
        operator = Browser(root)
        operator.sign_in()
        wrong = operator.write("POST", "/api/enrollments", {"name": "mini", "ip": "10.1.2.3"}).body["enrollment_token"]
        right = operator.write("POST", "/api/enrollments", {"name": "dgx", "ip": "127.0.0.1"}).body["enrollment_token"]
        expect(Browser(root).request("POST", "/v1/agents/enroll", {"enrollment_token": wrong, "name": "mini"}, origin=None).status == 401, "a wrong-address token worked")
        expect(Browser(root).request("POST", "/v1/agents/enroll", {"enrollment_token": right, "name": "dgx"}, origin=None).status == 200, "the right-address token failed")
        for bad_ip in ("999.1.1.1", "1.2.3", "a.b.c.d", "10.0.0.1; reboot", "-iL"):
            expect(operator.write("POST", "/api/enrollments", {"name": "x", "ip": bad_ip}).status == 400, f"ip {bad_ip!r} was accepted")


def check_bad_scan_settings_stop_the_root_from_starting():
    bad = ["SCAN_SUBNET=8.8.8.0/24", "SCAN_SUBNET=10.0.0.0/8", "SCAN_SUBNET=192.168.1.0/24; reboot", "ROUTER_URL=http://admin:pw@192.168.1.1", "ROUTER_URL=http://router.local",
           "ROUTER_URL=file:///etc/passwd", "AGENT_PORT=99999"]
    for line in bad:
        root = RunningRoot(env_text=f"ALLOWED_EMAILS=kurnia@example.com\n{line}\n")
        try:
            root.start()
        except AssertionError:
            code, text = root.exit_text()
            expect(code != 0, f"{line}: exit code {code}")
            continue
        finally:
            root.stop()
        raise AssertionError(f"the Root started with {line}")


CHECKS = [
    check_scan_setup_describes_what_is_available, check_a_scan_merges_router_nmap_and_arp, check_hostile_device_names_are_cleaned,
    check_a_scan_only_targets_the_configured_subnet, check_only_one_scan_runs_at_a_time, check_scans_need_a_session_and_csrf,
    check_scans_are_rate_limited, check_a_wrong_router_password_does_not_break_the_scan, check_a_scan_works_without_a_router,
    check_a_scan_works_without_nmap_and_fails_with_nothing, check_a_failing_nmap_is_reported_not_hidden,
    check_adding_found_devices_makes_pinned_tokens, check_add_refuses_bad_requests, check_a_pinned_invite_works_only_from_its_address,
    check_bad_scan_settings_stop_the_root_from_starting,
]
