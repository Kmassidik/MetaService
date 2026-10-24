"""The parent's public ports (sandbox/README.md, "Addresses"): an opaque 16-character label, a short-lived token, and a forwarder
that carries the request into the sandbox and the answer back.

Runs a real Root against the Fake Agent, which pretends a program inside the sandbox answers by echoing what it was asked. That is
what makes the forwarder checkable end to end: the label resolves, the token is checked before the machine is called, the path and
query arrive (minus our token), and the helper's status, headers and body come back as they were. The helper's real proxy is still a
later slice; a helper that answers 501 is passed through as 501.
"""
import calendar
import threading
import time
from contextlib import contextmanager

from agent.fake.engine import FakeEngine, MachineSpec
from agent.fake.server import make_server
from contract.root_tests.support import Browser, _free_port, expect, good_heartbeat, running

DOMAIN = "sandbox.test"
API_KEY_HEADER = "X-API-Key"
SANDBOXES = "/v2/sandboxes"
TOKEN = "token"
# A label nobody exposed: sixteen characters of the same alphabet a real one uses.
UNKNOWN_LABEL = "aaaaaaaaaaaaaaaa"
LIFETIME_SECONDS = 15 * 60


class FakeMachine:
    """The Fake Agent on one chosen port, with the machine token the Root enrolled: the Root calls it as it would a real helper."""

    def __init__(self, port, token, sandbox=True):
        self.server = make_server(FakeEngine(MachineSpec(sandbox=sandbox)), token, "127.0.0.1", port)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self):
        self.server.shutdown()
        self.server.server_close()


class Ports:
    """One Root with a team and a sandbox, and helpers for its API and its port hosts."""

    def __init__(self, root, browser, key, sandbox_id):
        self.root = root
        self.browser = browser
        self.key = key
        self.sandbox_id = sandbox_id

    def api(self, method, path, body=None):
        """A call with an API key and no cookie: the API refuses a request that carries a session."""
        return self.browser.request(method, path, body, headers={API_KEY_HEADER: self.key}, cookies=False, origin=None)

    def port(self, method, host, path, token=None, headers=None, raw=None, body=None):
        """A request to a port host, the way a program makes it: the Host names the label, and the token is in the query or the header."""
        sent = {"Host": host, **(headers or {})}
        if token is not None:
            sent.setdefault("X-Port-Token", token)
        return self.browser.request(method, path, body, headers=sent, raw=raw, cookies=False, origin=None)

    def expose(self, port, sandbox_id=None):
        return self.api("POST", f"{SANDBOXES}/{sandbox_id or self.sandbox_id}/ports", {"port": port})

    def exposed(self, port):
        """The host and token for a port, whether this call made the row or found it."""
        reply = self.expose(port)
        expect(reply.status in (200, 201), f"exposing {port} gave {reply.status}: {reply.raw[:200]!r}")
        return reply.body


def _enroll(browser, name="sandbox-1"):
    """Invite a machine and enroll it, answering the two tokens a real install keeps: the machine token it reports with and the
    command token the Root calls it with. The Fake Agent authenticates with the command token, as a real helper does."""
    invite = browser.write("POST", "/api/enrollments", {"name": name})
    expect(invite.status == 201, f"the invite gave {invite.status}: {invite.raw[:200]!r}")
    reply = Browser(browser.root).request("POST", "/v1/agents/enroll",
                                          {"enrollment_token": invite.body["enrollment_token"], "name": name}, origin=None)
    expect(reply.status == 200, f"the enroll gave {reply.status}: {reply.raw[:200]!r}")
    return reply.body["machine_token"], reply.body["command_token"]


def _heartbeat(browser, token, agent_port):
    """A heartbeat that says the machine runs sandboxes and where its helper listens, as a real helper's does."""
    body = good_heartbeat(workloads=[])
    body["agent_port"] = agent_port
    body["facts"]["capabilities"]["sandbox"] = True
    body["facts"]["sandbox"] = {
        "engine": {"name": "simulated", "version": None},
        "max_running": 8, "running": 0, "paused": 0,
        "max_vcpu": 16, "max_ram_mb": 32768, "max_disk_mb": 102400,
        "booked": {"vcpu": 0, "ram_mb": 0, "disk_mb": 0},
        "templates": [{"id": "base", "build": "1", "ready": True}],
        "changes": 0,
    }
    reply = Browser(browser.root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {token}"}, origin=None)
    expect(reply.status == 204, f"the heartbeat gave {reply.status}: {reply.raw[:200]!r}")


@contextmanager
def ports(team="Ports"):
    """A Root with one team, one key, one enrolled machine (the Fake Agent) and one running sandbox."""
    agent_port = _free_port()
    with running(env_text=f"SANDBOX_DOMAIN={DOMAIN}\nAGENT_PORT={agent_port}\n") as root:
        browser = Browser(root)
        made = browser.write("POST", "/api/sandboxes/keys", {"team_name": team})
        expect(made.status == 201, f"making a key gave {made.status}: {made.raw[:200]!r}")
        machine_token, command_token = _enroll(browser)
        machine = FakeMachine(agent_port, command_token)
        try:
            _heartbeat(browser, machine_token, agent_port)
            one = Ports(root, browser, made.body["key"], "")
            created = one.api("POST", SANDBOXES, {"templateID": "base", "timeout": 300})
            expect(created.status == 201, f"creating a sandbox gave {created.status}: {created.raw[:200]!r}")
            one.sandbox_id = created.body["sandboxID"]
            yield one
        finally:
            machine.stop()


def _is_label(text):
    return len(text) == 16 and all(character in "abcdefghijklmnopqrstuvwxyz234567" for character in text)


def _seconds(iso):
    """Unix seconds of a contract time (`2026-10-24T09:30:00Z`)."""
    return calendar.timegm(time.strptime(iso, "%Y-%m-%dT%H:%M:%SZ"))


# ---- exposing a port -------------------------------------------------------------

def check_exposing_a_port_answers_an_opaque_label_host_and_a_short_lived_token():
    with ports() as one:
        answer = one.exposed(8080)
        expect(set(answer) == {"host", "token", "expiresAt"}, f"the expose answered {sorted(answer)}")
        label, _, domain = answer["host"].partition(".")
        expect(_is_label(label), f"the host's label is not 16 characters of lowercase base32: {answer['host']}")
        expect(domain == DOMAIN, f"the host is not on the sandbox domain: {answer['host']}")
        expect("8080" not in answer["host"], f"the port is in the public name: {answer['host']}")
        expect(answer["token"], "the expose answered no token")
        expires = _seconds(answer["expiresAt"])
        expect(abs(expires - (time.time() + LIFETIME_SECONDS)) < 120, f"the token does not live about 15 minutes: {answer['expiresAt']}")


def check_exposing_the_same_port_twice_answers_the_same_host():
    with ports() as one:
        first = one.exposed(8080)
        again = one.expose(8080)
        expect(again.status == 200, f"the second expose gave {again.status}: {again.raw[:200]!r}")
        expect(again.body["host"] == first["host"], f"one port got two hosts: {first['host']} then {again.body['host']}")
        expect(again.body["token"], "the second expose answered no token")
        other = one.exposed(8081)
        expect(other["host"] != first["host"], f"two ports share one host: {other['host']}")


def check_exposing_a_port_refuses_what_it_cannot_serve():
    with ports() as one:
        expect(one.expose(0).status == 400, "port 0 was accepted")
        expect(one.expose(65536).status == 400, "port 65536 was accepted")
        expect(one.api("POST", f"{SANDBOXES}/{one.sandbox_id}/ports", {"port": "8080"}).status == 400, "a string port was accepted")
        expect(one.api("POST", f"{SANDBOXES}/{one.sandbox_id}/ports", {"port": 8080, "path": "/"}).status == 400, "an extra field was accepted")
        unknown = one.expose(8080, sandbox_id="abcdefghij0123456789")
        expect(unknown.status == 404, f"an unknown sandbox gave {unknown.status}: {unknown.raw[:200]!r}")
        anonymous = one.browser.request("POST", f"{SANDBOXES}/{one.sandbox_id}/ports", {"port": 8080}, cookies=False, origin=None)
        expect(anonymous.status == 401, f"an expose without a key gave {anonymous.status}")


def check_exposing_a_port_of_another_team_is_no_such_sandbox():
    with ports() as one:
        other = one.browser.write("POST", "/api/sandboxes/keys", {"team_name": "Someone else"})
        expect(other.status == 201, f"making a second key gave {other.status}")
        reply = one.browser.request("POST", f"{SANDBOXES}/{one.sandbox_id}/ports", {"port": 8080},
                                    headers={API_KEY_HEADER: other.body["key"]}, cookies=False, origin=None)
        expect(reply.status == 404, f"another team's sandbox gave {reply.status}: {reply.raw[:200]!r}")


def check_exposing_a_port_of_a_paused_or_ended_sandbox_is_a_conflict():
    with ports() as one:
        paused = one.browser.write("POST", f"/api/sandboxes/{one.sandbox_id}/pause")
        expect(paused.status == 204, f"pausing gave {paused.status}: {paused.raw[:200]!r}")
        refused = one.expose(8080)
        expect(refused.status == 409 and refused.body["error_code"] == "sandbox_not_running",
               f"a paused sandbox gave {refused.status}: {refused.raw[:200]!r}")
        killed = one.browser.write("POST", f"/api/sandboxes/{one.sandbox_id}/kill")
        expect(killed.status == 204, f"killing gave {killed.status}: {killed.raw[:200]!r}")
        after = one.expose(8080)
        expect(after.status == 409 and after.body["error_code"] == "sandbox_not_running",
               f"an ended sandbox gave {after.status}: {after.raw[:200]!r}")


# ---- forwarding ------------------------------------------------------------------

def check_the_forwarder_carries_the_request_into_the_sandbox():
    with ports() as one:
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        reply = one.port("GET", host, f"/dir/index.html?q=a%20b&{TOKEN}={token}", token=token,
                         headers={"Authorization": "Bearer the-program's-own"})
        expect(reply.status == 200, f"the forwarded GET gave {reply.status}: {reply.raw[:200]!r}")
        expect(reply.body["method"] == "GET", f"the method did not arrive: {reply.body}")
        expect(reply.body["sandbox"] == one.sandbox_id and reply.body["port"] == 8080, f"the forwarded address is wrong: {reply.body}")
        expect(reply.body["path"] == "dir/index.html", f"the path did not arrive: {reply.body['path']!r}")
        expect(reply.body["query"] == "q=a%20b", f"the query did not arrive minus our token: {reply.body['query']!r}")
        expect(reply.body["port_token"] is False, "our token was passed on to the helper in the query")
        expect(reply.body["port_token_header"] is False, "our token header was passed on to the helper")
        expect(reply.body["command_token"] is True, "the helper was called without the command token")
        expect(reply.body["authorization"] == "Bearer the-program's-own", f"the caller's Authorization did not pass through: {reply.body['authorization']!r}")


def check_the_forwarder_carries_a_body_and_other_methods():
    with ports() as one:
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        reply = one.port("POST", host, "/submit?x=1", token=token, raw=b"hello sandbox")
        expect(reply.status == 200, f"the forwarded POST gave {reply.status}: {reply.raw[:200]!r}")
        expect(reply.body["method"] == "POST", f"the method did not arrive: {reply.body}")
        expect(reply.body["body"] == "hello sandbox", f"the body did not arrive: {reply.body['body']!r}")
        expect(reply.body["query"] == "x=1", f"the query did not arrive: {reply.body['query']!r}")


def check_the_token_can_travel_in_the_header_instead_of_the_query():
    with ports() as one:
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        reply = one.port("GET", host, "/header-only", token=token)
        expect(reply.status == 200, f"a header token gave {reply.status}: {reply.raw[:200]!r}")
        expect(reply.body["port_token"] is False and reply.body["port_token_header"] is False, "our token reached the helper")


def check_a_port_host_refuses_a_token_it_did_not_give_out():
    with ports() as one:
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        other = one.exposed(8081)
        for name, reply in {
            "no token": one.port("GET", host, "/nothing"),
            "an empty token": one.port("GET", host, "/nothing", token=""),
            "a made-up token": one.port("GET", host, "/nothing", token="v1." + "a" * 80),
            "another host's token": one.port("GET", host, "/nothing", token=other["token"]),
        }.items():
            expect(reply.status == 401, f"{name} gave {reply.status}: {reply.raw[:200]!r}")
            expect(reply.body["code"] == 401 and reply.body["error_code"] == "invalid_port_token",
                   f"{name} answered {reply.body}")


def check_an_unknown_label_is_the_same_closed_door():
    with ports() as one:
        reply = one.port("GET", f"{UNKNOWN_LABEL}.{DOMAIN}", "/", token="v1." + "a" * 80)
        expect(reply.status == 502, f"an unknown label gave {reply.status}: {reply.raw[:200]!r}")
        expect(reply.body["error_code"] == "port_not_found", f"an unknown label answered {reply.body}")


def check_the_helpers_answer_passes_through_unchanged():
    with ports() as one:
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        for status in (501, 418):
            reply = one.port("GET", host, "/no-proxy", token=token, headers={"X-Fake-Port-Status": str(status)})
            expect(reply.status == status, f"the helper's {status} came back as {reply.status}: {reply.raw[:200]!r}")
            expect(reply.body["error"]["code"] == "fake_port_status", f"the helper's body was rewritten: {reply.body}")


def check_a_port_host_does_not_swallow_the_panel_or_the_api():
    with ports() as one:
        panel = one.browser.request("GET", "/api/sandboxes", origin=None)
        expect(panel.status == 200, f"the panel's own sandbox list gave {panel.status}: {panel.raw[:200]!r}")
        host = one.exposed(8080)["host"]
        token = one.exposed(8080)["token"]
        forwarded = one.port("GET", host, "/api/sandboxes", token=token)
        expect(forwarded.status == 200 and forwarded.body.get("path") == "api/sandboxes",
               f"a panel path on a port host was answered by the panel: {forwarded.status} {forwarded.raw[:200]!r}")
        health = one.port("GET", host, "/health", token=token)
        expect(health.status == 200 and health.body.get("path") == "health",
               f"the parent's own /health answered for a port host: {health.status} {health.raw[:200]!r}")


CHECKS = [value for name, value in sorted(globals().items()) if name.startswith("check_")]
