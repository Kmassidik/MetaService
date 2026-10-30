"""What the MCP checks share: a real Root with fake helpers that keep sending heartbeats, an MCP client that speaks JSON-RPC over HTTP, and a few
direct reads and writes of the Root's database for the things only time changes (an expired token, an old request, the join-share address)."""
import copy
import json
import sqlite3
import threading
import time
from contextlib import contextmanager

from agent.fake.engine import MachineSpec
from contract.root_tests.checks_gpu import GpuHelper
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.checks_ssh_keys import ED25519 as SSH_KEY  # noqa: F401 - the tests' public key
from contract.root_tests.support import Browser, expect, good_heartbeat, running

BEAT_SECONDS = 0.25
FAKE_TOKEN_TEXT = "msk_" + "Z" * 43
CARD = {"vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768}
SHARED_ADDRESS = "10.77.0.2"


class Machine:
    """One enrolled machine with a fake helper behind it. `shared` makes the parent see it at a Share a PC address."""

    def __init__(self, operator, root, name, spec, shared=False):
        self.name, self.shared, self.root = name, shared, root
        self.machine_token, command_token = enroll(operator, name)
        self.helper = GpuHelper(command_token, spec)
        if shared:
            self._pin_the_address()

    def _pin_the_address(self):
        """A heartbeat from this computer arrives from loopback, so the Root would record 127.0.0.1. A trigger puts the Share a PC address back inside the same write."""
        sql(self.root, f"CREATE TRIGGER pin_{self.name.replace('-', '_')} AFTER UPDATE OF ip ON machines WHEN NEW.id = '{self.name}' AND NEW.ip IS NOT '{SHARED_ADDRESS}' "
                       f"BEGIN UPDATE machines SET ip = '{SHARED_ADDRESS}' WHERE id = NEW.id; END")

    def beat(self):
        body = copy.deepcopy(good_heartbeat())
        facts = self.helper.engine.facts()
        body["facts"] = {key: facts[key] for key in ("os", "arch", "cpu_cores", "cpu_model", "hardware", "ram_total_mb", "disk_total_gb", "free_ram_mb", "free_disk_gb", "gpu", "capabilities", "engine") if key in facts}
        body["workloads"] = self.helper.engine.workloads()
        body["agent_port"] = self.helper.port
        reply = Browser(self.root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {self.machine_token}"}, origin=None)
        expect(reply.status == 204, f"heartbeat gave {reply.status}")


def sql(root, statement, *params):
    connection = sqlite3.connect(f"{root.dir}/root.sqlite3", timeout=5)
    try:
        rows = connection.execute(statement, params).fetchall()
        connection.commit()
        return rows
    finally:
        connection.close()


class Client:
    """An AI client: a Bearer token and JSON-RPC calls. No cookie, no Origin unless asked."""

    def __init__(self, root, token=None, version="2025-06-18"):
        self.root, self.token, self.version = root, token, version
        self.web = Browser(root, auto_login=False)
        self.ids = 0

    def post(self, message=None, raw=None, token="own", headers=None, origin=None):
        sent = dict(headers or {})
        bearer = self.token if token == "own" else token
        if bearer:
            sent["Authorization"] = f"Bearer {bearer}"
        if self.version:
            sent.setdefault("MCP-Protocol-Version", self.version)
        sent.setdefault("Accept", "application/json, text/event-stream")
        return self.web.request("POST", "/mcp", message, raw=raw, headers=sent, origin=origin, cookies=False)

    def rpc(self, method, params=None, **kwargs):
        self.ids += 1
        message = {"jsonrpc": "2.0", "id": self.ids, "method": method}
        if params is not None:
            message["params"] = params
        return self.post(message, **kwargs)

    def tool(self, name, arguments=None, **kwargs):
        """The tool result: its `isError`, the JSON the text carries, and the raw reply."""
        reply = self.rpc("tools/call", {"name": name, "arguments": arguments or {}}, **kwargs)
        expect(reply.status == 200 and reply.body and "result" in reply.body, f"{name} gave {reply.status}: {reply.raw[:300]!r}")
        result = reply.body["result"]
        text = result["content"][0]["text"]
        return Result(result["isError"], json.loads(text), result, reply)


class Result:
    def __init__(self, is_error, data, result, reply):
        self.is_error, self.data, self.result, self.reply = is_error, data, result, reply

    @property
    def error(self):
        expect(self.is_error, f"expected a refusal, got {self.data}")
        return self.data["error"]

    def ok(self):
        expect(not self.is_error, f"expected success, got {self.data}")
        return self.data


@contextmanager
def parent(machines=None, beat_seconds=BEAT_SECONDS):
    """A Root, an operator session and fake helpers. `machines` is a list of (name, MachineSpec, shared). Heartbeats go on in the background."""
    machines = machines if machines is not None else [("mini", MachineSpec(), False)]
    with running() as root:
        operator = Browser(root)
        made = [Machine(operator, root, name, spec, shared) for name, spec, shared in machines]
        for machine in made:
            machine.beat()
        stop = threading.Event()

        def keep_beating():
            while not stop.wait(beat_seconds):
                for machine in made:
                    try:
                        machine.beat()
                    except Exception:  # noqa: BLE001 - the Root is going away at the end of the check
                        return

        thread = threading.Thread(target=keep_beating, daemon=True)
        thread.start()
        try:
            yield root, operator, {machine.name: machine for machine in made}
        finally:
            stop.set()
            thread.join(timeout=3)
            for machine in made:
                machine.helper.stop()


def make_token(operator, name="claude", **fields):
    """Creates a token in the panel way. Returns (text, info)."""
    reply = operator.write("POST", "/api/mcp/tokens", {"name": name, **fields})
    expect(reply.status == 201, f"token create gave {reply.status}: {reply.raw[:200]!r}")
    return reply.body["token"], reply.body["info"]


def client_for(root, operator, name="claude", **fields):
    text, info = make_token(operator, name, **fields)
    return Client(root, text), text, info


def everything_said(root, operator):
    """All the text the operator API and the audit trail hold, to search for secrets."""
    parts = [operator.request("GET", path).raw.decode() for path in ("/api/mcp/tokens", "/api/mcp/approvals", "/api/mcp/activity?limit=200", "/api/audit?limit=200", "/api/mcp/info")]
    parts += [str(row) for row in sql(root, "SELECT * FROM audit_log")]
    return "\n".join(parts)


def wait_until(condition, seconds=15, what="the condition"):
    deadline = time.time() + seconds
    while time.time() < deadline:
        value = condition()
        if value:
            return value
        time.sleep(0.2)
    raise AssertionError(f"timed out waiting for {what}")
