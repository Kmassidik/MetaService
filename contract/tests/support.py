"""Small helpers shared by the conformance checks."""
import itertools
import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass

from contract import spec

COMMAND_WAIT_SECONDS = 10
POLL_SECONDS = 0.05
REQUEST_TIMEOUT_SECONDS = 15


class CheckFailed(AssertionError):
    pass


def expect(condition, message):
    if not condition:
        raise CheckFailed(message)


@dataclass
class Reply:
    status: int
    headers: dict
    body: object
    raw: bytes


class Client:
    def __init__(self, base_url, token):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def request(self, method, path, body=None, token="default", headers=None, raw=None):
        data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
        request = urllib.request.Request(self.base_url + path, data=data, method=method)
        use_token = self.token if token == "default" else token
        if use_token is not None:
            request.add_header("Authorization", f"Bearer {use_token}")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        for name, value in (headers or {}).items():
            request.add_header(name, value)
        return self._send(request)

    def _send(self, request):
        try:
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
                return _reply(response.status, response.headers, response.read())
        except urllib.error.HTTPError as error:
            return _reply(error.code, error.headers, error.read())


def _reply(status, headers, raw):
    try:
        body = json.loads(raw) if raw else None
    except ValueError:
        body = None
    return Reply(status, dict(headers.items()), body, raw)


class Context:
    """What every check receives: a client plus a source of unique ids."""

    def __init__(self, client):
        self.client = client
        self._counter = itertools.count(1)
        self._run = format(int(time.time() * 1000) % 0xFFFFFFF, "x")

    def new_id(self, prefix="t"):
        return f"{prefix}-{self._run}-{next(self._counter)}"

    def get(self, path):
        return self.client.request("GET", path)

    def post(self, path, body=None, **kwargs):
        return self.client.request("POST", path, body, **kwargs)

    def delete(self, path, **kwargs):
        return self.client.request("DELETE", path, **kwargs)

    def facts(self):
        return self.get("/v1/facts").body

    def kind(self):
        """The kind of workload this machine can run: a container when it can, otherwise a VM."""
        return "container" if self.facts()["capabilities"]["container"] else "vm"

    def workloads(self):
        return self.get("/v1/workloads").body["workloads"]

    def wait_for(self, command_id, state="succeeded"):
        deadline = time.time() + COMMAND_WAIT_SECONDS
        while time.time() < deadline:
            reply = self.get(f"/v1/commands/{command_id}")
            expect(reply.status == 200, f"command {command_id} lookup gave {reply.status}")
            if reply.body["state"] == state:
                return reply.body
            time.sleep(POLL_SECONDS)
        raise CheckFailed(f"command {command_id} did not reach {state} in {COMMAND_WAIT_SECONDS}s")

    def create_small(self, **overrides):
        body = {"command_id": self.new_id("c"), "name": self.new_id("w"), "kind": self.kind(),
                "cpu": 1, "ram_mb": 512, "disk_gb": 1}
        body.update(overrides)
        reply = self.post("/v1/workloads", body)
        expect(reply.status == 202, f"create gave {reply.status}: {reply.body}")
        done = self.wait_for(reply.body["command_id"])
        return done["workload_id"], body


def expect_schema(name, instance, label):
    found = spec.problems(name, instance)
    expect(not found, f"{label} does not fit {name}: {found}")


def expect_error(reply, status, label):
    expect(reply.status == status, f"{label}: wanted {status}, got {reply.status} {reply.body}")
    expect_schema("Error", reply.body, label)
