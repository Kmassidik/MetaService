"""HTTP front of the Fake Agent. Implements the Agent half of contract/openapi.yaml."""
import hmac
import itertools
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from agent.fake.apps import MODES as APP_INSTALL_MODES
from agent.fake.apps import AppInstallFailed
from agent.fake.engine import HOST_CPU_MODEL, NotFound, Refused, SshdInstallFailed
from agent.fake.ssh_keys import is_valid_key
from agent.fake.stats import FakeStats, wants_processes
from agent.fake.terminal import Consoles, Session
from contract import spec, wsproto

MAX_BODY_BYTES = 64 * 1024
MAX_DRAIN_BYTES = 1024 * 1024
MAX_INSTALL_DELAY_SECONDS = 10
ID_PATTERN = r"[a-z0-9][a-z0-9-]{0,62}"
JSON_TYPE = "application/json"
SECRET_BODY_MESSAGE = "the body must be {\"keys\": [up to 20 key lines]}"
# The kind each CPU setting of a create belongs to, and the cap's unit: 100 is one whole CPU.
CPU_FIELD_KINDS = {"cpu_sockets": "vm", "cpu_type": "vm", "cpu_flags": "vm", "cpu_limit_percent": "container"}
PERCENT_PER_CPU = 100


# Only these refusals carry the numbers behind them (the Refusal schema); any other 409 is a plain Error.
ROOM_REFUSALS = ("not_enough_room", "missing_capability")


def refusal_error(refused):
    plain = {"code": refused.code, "message": refused.message}
    if refused.code not in ROOM_REFUSALS:
        return plain
    return {**plain, "resource": refused.resource, "needed": refused.needed, "free": refused.free}


class ApiError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


class AgentHandler(BaseHTTPRequestHandler):
    engine = None
    consoles = None
    stats = None
    token = b""
    server_version = "FakeAgent"
    _anon_ids = itertools.count(1)

    def log_message(self, *args):
        return

    # ---- plumbing --------------------------------------------------
    def do_GET(self):
        self._serve("GET")

    def do_POST(self):
        self._serve("POST")

    def do_PUT(self):
        self._serve("PUT")

    def do_DELETE(self):
        self._serve("DELETE")

    def _serve(self, method):
        try:
            self._require_token()
            handler, params = self._route(method)
            handler(self, **params)
        except ApiError as error:
            self._send(error.status, {"error": {"code": error.code, "message": error.message}})
        except AppInstallFailed as failed:
            self._send(502, {"error": {"code": "app_install_failed", "message": failed.message, "log_tail": failed.log_tail}})
        except Refused as refused:
            self._send(409, {"error": refusal_error(refused)})
        except NotFound:
            self._send(404, {"error": {"code": "not_found", "message": "no such thing"}})
        except Exception:  # noqa: BLE001 - last resort: a clean 500 that reveals nothing
            self._send(500, {"error": {"code": "internal", "message": "internal error"}})

    def _require_token(self):
        header = self.headers.get("Authorization", "")
        supplied = header.removeprefix("Bearer ").encode()
        if not hmac.compare_digest(supplied, self.token):
            raise ApiError(401, "unauthorized", "missing or wrong token")

    def _route(self, method):
        path = self.path.split("?", 1)[0]
        for route_method, pattern, handler in ROUTES:
            match = re.fullmatch(pattern, path)
            if match and route_method == method:
                return handler, match.groupdict()
        raise ApiError(404, "not_found", "no such path")

    def _body(self, schema_name, secret=False):
        """The checked JSON body. With `secret`, a refusal never repeats what the body held (a schema message quotes the value)."""
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length > MAX_BODY_BYTES:
            self.rfile.read(min(length, MAX_DRAIN_BYTES))
            raise ApiError(413, "too_large", "request body too large")
        try:
            body = json.loads(self.rfile.read(length) or b"null")
        except ValueError:
            raise ApiError(400, "invalid_json", "body is not valid JSON") from None
        found = spec.problems(schema_name, body)
        if found:
            raise ApiError(400, "invalid_input", SECRET_BODY_MESSAGE if secret else "; ".join(found))
        return body

    def _command_id(self):
        supplied = self.headers.get("X-Command-Id")
        if supplied is None:
            return f"cmd-{next(self._anon_ids)}"
        if spec.problems("Id", supplied):
            raise ApiError(400, "invalid_input", "X-Command-Id is not a valid id")
        return supplied

    def _send(self, status, body=None):
        payload = b"" if body is None else json.dumps(body).encode()
        self.send_response(status)
        self.send_header(spec.CONTRACT_HEADER, spec.CONTRACT_VERSION)
        self.send_header("Content-Type", JSON_TYPE)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    # ---- endpoints -------------------------------------------------
    def health(self):
        self._send(200, self.engine.health())

    def facts(self):
        self._send(200, self.engine.facts())

    def get_stats(self):
        query = urlsplit(self.path).query
        self.stats.queries.append(query)
        with_processes = wants_processes(query)
        if with_processes is None:
            raise ApiError(400, "invalid_input", "processes must be 1 or 0")
        self._send(200, self.stats.reading(with_processes))

    def list_images(self):
        if not self.engine.spec.serves_images:
            raise ApiError(404, "not_found", "no such path")
        self._send(200, self.engine.images())

    def list_workloads(self):
        self._send(200, {"workloads": self.engine.workloads()})

    def create_workload(self):
        body = self._body("WorkloadCreate")
        self._check_gpu_memory_limit(body)
        self._check_cpu_options(body)
        record = self.engine.create(body)
        self._send(202, _accepted(record))

    def _check_gpu_memory_limit(self, body):
        if "gpu_memory_gb" not in body:
            return
        if body["kind"] != "container" or body.get("gpu_mode", "none") != "container":
            raise ApiError(400, "invalid_input", "gpu_memory_gb can only be set on a container with gpu_mode container")
        if not (self.engine.spec.gpu_in_container and self.engine.spec.gpu_memory_limit):
            raise ApiError(400, "invalid_input", "this helper cannot limit GPU memory")

    def _check_cpu_options(self, body):
        """The CPU settings of Proxmox's Processors window: each only on its kind and only when this helper offers it, the sockets dividing `cpu` and the cap
        at most `cpu` x 100. The schema has already checked each value on its own."""
        for name, kind in CPU_FIELD_KINDS.items():
            if name in body and body["kind"] != kind:
                raise ApiError(400, "invalid_input", f"{name} can only be set when kind is {kind}")
        offer, cpu = self.engine.cpu_offer(), body["cpu"]
        if "cpu_sockets" in body and not offer.get("cpu_topology"):
            raise ApiError(400, "invalid_input", "this helper cannot spread a VM's CPUs over sockets")
        if "cpu_sockets" in body and cpu % body["cpu_sockets"]:
            raise ApiError(400, "invalid_input", f"cpu ({cpu}) must be a multiple of cpu_sockets ({body['cpu_sockets']})")
        models = offer.get("cpu_models", [HOST_CPU_MODEL])
        if "cpu_type" in body and body["cpu_type"] not in models:
            raise ApiError(400, "invalid_input", "cpu_type must be one of this helper's CPU models: " + ", ".join(models))
        for flag in body.get("cpu_flags", {}):
            if flag not in offer.get("cpu_flags", []):
                raise ApiError(400, "invalid_input", f"this helper cannot switch the CPU flag {flag}")
        if "cpu_limit_percent" in body and not offer.get("cpu_limit"):
            raise ApiError(400, "invalid_input", "this helper cannot cap a container's CPU time")
        if body.get("cpu_limit_percent", 0) > cpu * PERCENT_PER_CPU:
            raise ApiError(400, "invalid_input", f"cpu_limit_percent can be at most cpu x {PERCENT_PER_CPU} ({cpu * PERCENT_PER_CPU} here)")

    def start_workload(self, id):
        self._send(202, _accepted(self.engine.set_state(self._command_id(), id, "start", "running")))

    def stop_workload(self, id):
        self._send(202, _accepted(self.engine.set_state(self._command_id(), id, "stop", "stopped")))

    def delete_workload(self, id):
        self._send(202, _accepted(self.engine.delete(self._command_id(), id)))

    def install_bundle(self):
        self._send(202, _accepted(self.engine.install_bundle(self._body("BundleInstall"))))

    def uninstall_bundle(self):
        self._send(202, _accepted(self.engine.uninstall_bundle(self._body("BundleUninstall"))))

    def terminal(self, id):
        """A WebSocket console: /bin/sh in a pty. 404 unknown, 409 not running or already open, 426 when this is not an upgrade (everything else passed)."""
        workload = next((w for w in self.engine.workloads() if w["id"] == id), None)
        if workload is None:
            raise NotFound(id)
        if workload["state"] != "running":
            raise ApiError(409, "not_running", "the workload is not running")
        key = self.headers.get("Sec-WebSocket-Key")
        is_upgrade = self.headers.get("Upgrade", "").lower() == "websocket" and key
        if self.consoles.is_open(id) or (is_upgrade and not self.consoles.claim(id)):
            raise ApiError(409, "console_open", "this workload already has a console")
        if not is_upgrade:
            raise ApiError(426, "upgrade_required", "this route is a WebSocket")
        try:
            self._run_console(id, key)
        finally:
            self.consoles.release(id)

    def _run_console(self, id, key):
        self.wfile.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Accept: {wsproto.accept_key(key)}\r\n{spec.CONTRACT_HEADER}: {spec.CONTRACT_VERSION}\r\n\r\n").encode())
        self.wfile.flush()
        self.close_connection = True
        Session(self.connection, self.rfile, lambda: self._is_running(id)).run()

    def _is_running(self, id):
        return any(w["id"] == id and w["state"] == "running" for w in self.engine.workloads())

    def gpu_check(self, id):
        self._send(200, self.engine.gpu_check(id))

    def put_ssh_keys(self, id):
        body = self._body("SshKeysApply", secret=True)
        if not all(is_valid_key(line) for line in body["keys"]):
            raise ApiError(400, "invalid_input", "each key must be a key type, base64 and an optional comment")
        try:
            self._send(200, self.engine.apply_ssh_keys(id, body["keys"], body.get("install_sshd", False)))
        except SshdInstallFailed as failed:
            raise ApiError(502, "sshd_install_failed", str(failed)) from None

    def put_app(self, id):
        if not self.engine.spec.serves_apps:
            raise ApiError(404, "not_found", "no such path")
        body = self._body("AppInstall")
        self._send(200, self.engine.install_app(id, body["app"]))

    def show_apps(self, id):
        """Test tool, not part of the contract: the apps now installed in the VM."""
        self._send(200, {"apps": self.engine.apps_in(id)})

    def set_app_install(self):
        """Test tool, not part of the contract: how app installs go. Body: {"mode": "works" | "fails", "delay_seconds": 0 to 10 (default 0)}."""
        body = self._tool_body_with_optional({"mode": str}, {"delay_seconds": (int, float)})
        delay = body.get("delay_seconds", 0)
        if body["mode"] not in APP_INSTALL_MODES or isinstance(delay, bool) or not 0 <= delay <= MAX_INSTALL_DELAY_SECONDS:
            raise ApiError(400, "invalid_input", f"mode must be works or fails and delay_seconds 0 to {MAX_INSTALL_DELAY_SECONDS}")
        self.engine.set_app_install(body["mode"], delay)
        self._send(204)

    def show_ssh_keys(self, id):
        """Test tool, not part of the contract: the keys now in the VM."""
        self._send(200, {"keys": self.engine.ssh_keys_of(id)})

    def set_sshd(self):
        """Test tool, not part of the contract: what later applies report about sshd. Body: {"state": "running" | "installed" | "missing"}."""
        state = self._tool_body({"state": str})["state"]
        if state not in ("running", "installed", "missing"):
            raise ApiError(400, "invalid_input", "state must be running, installed or missing")
        self.engine.set_sshd(state)
        self._send(204)

    def set_ssh_install(self):
        """Test tool, not part of the contract: how install_sshd goes. Body: {"mode": "works" | "fails", "delay_seconds": 0 to 10 (default 0)}."""
        body = self._tool_body_with_optional({"mode": str}, {"delay_seconds": (int, float)})
        delay = body.get("delay_seconds", 0)
        if body["mode"] not in ("works", "fails") or isinstance(delay, bool) or not 0 <= delay <= MAX_INSTALL_DELAY_SECONDS:
            raise ApiError(400, "invalid_input", f"mode must be works or fails and delay_seconds 0 to {MAX_INSTALL_DELAY_SECONDS}")
        self.engine.set_ssh_install(body["mode"], delay)
        self._send(204)

    def quit_by_itself(self, id):
        """Test tool, not part of the contract: makes a VM stop on its own with a reason. Body: {"exit_code": int or null, "log_tail": text}."""
        body = self._tool_body({"exit_code": (int, type(None)), "log_tail": str})
        self.engine.quit_by_itself(id, body["exit_code"], body["log_tail"])
        self._send(204)

    def gpu_usage(self):
        """Test tool, not part of the contract: simulates the watchdog. Body: {"workload": id, "used_gb": number}. Over the VM's limit it stops the VM with a reason."""
        body = self._tool_body({"workload": str, "used_gb": (int, float)})
        if isinstance(body["used_gb"], bool) or body["used_gb"] < 0:
            raise ApiError(400, "invalid_input", "used_gb must be a number of GB, 0 or more")
        self.engine.report_gpu_usage(body["workload"], body["used_gb"])
        self._send(204)

    def create_fails(self):
        """Test tool, not part of the contract: every later create fails with this reason. Body: {"error": text or null}."""
        self.engine.fail_creates_with(self._tool_body({"error": (str, type(None))})["error"])
        self._send(204)

    def _tool_body_with_optional(self, required, optional):
        """Like _tool_body, but the fields in `optional` may be left out."""
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            body = json.loads(self.rfile.read(min(length, MAX_BODY_BYTES)) or b"null")
        except ValueError:
            raise ApiError(400, "invalid_json", "body is not valid JSON") from None
        kinds = {**required, **optional}
        valid = isinstance(body, dict) and set(required) <= set(body) <= set(kinds) and all(isinstance(body[key], kinds[key]) for key in body)
        if not valid:
            raise ApiError(400, "invalid_input", "the test tool wants " + ", ".join(required) + " and maybe " + ", ".join(optional))
        return body

    def _tool_body(self, fields):
        length = int(self.headers.get("Content-Length", "0") or 0)
        try:
            body = json.loads(self.rfile.read(min(length, MAX_BODY_BYTES)) or b"null")
        except ValueError:
            raise ApiError(400, "invalid_json", "body is not valid JSON") from None
        if not isinstance(body, dict) or set(body) != set(fields) or not all(isinstance(body[key], kind) for key, kind in fields.items()):
            raise ApiError(400, "invalid_input", "the test tool wants exactly " + ", ".join(fields))
        return body

    def get_command(self, id):
        self._send(200, self.engine.command(id))


def _accepted(record):
    return {"command_id": record["command_id"], "state": record["state"]}


ROUTES = [
    ("GET", r"/v1/health", AgentHandler.health),
    ("GET", r"/v1/facts", AgentHandler.facts),
    ("GET", r"/v1/stats", AgentHandler.get_stats),
    ("GET", r"/v1/images", AgentHandler.list_images),
    ("GET", r"/v1/workloads", AgentHandler.list_workloads),
    ("POST", r"/v1/workloads", AgentHandler.create_workload),
    ("GET", rf"/v1/workloads/(?P<id>{ID_PATTERN})/terminal", AgentHandler.terminal),
    ("POST", rf"/v1/workloads/(?P<id>{ID_PATTERN})/gpu-check", AgentHandler.gpu_check),
    ("PUT", rf"/v1/workloads/(?P<id>{ID_PATTERN})/ssh-keys", AgentHandler.put_ssh_keys),
    ("PUT", rf"/v1/workloads/(?P<id>{ID_PATTERN})/app", AgentHandler.put_app),
    ("POST", rf"/v1/workloads/(?P<id>{ID_PATTERN})/start", AgentHandler.start_workload),
    ("POST", rf"/v1/workloads/(?P<id>{ID_PATTERN})/stop", AgentHandler.stop_workload),
    ("DELETE", rf"/v1/workloads/(?P<id>{ID_PATTERN})", AgentHandler.delete_workload),
    ("POST", r"/v1/bundle/install", AgentHandler.install_bundle),
    ("POST", r"/v1/bundle/uninstall", AgentHandler.uninstall_bundle),
    ("GET", rf"/v1/commands/(?P<id>{ID_PATTERN})", AgentHandler.get_command),
    ("POST", rf"/fake/workloads/(?P<id>{ID_PATTERN})/quit", AgentHandler.quit_by_itself),
    ("POST", r"/fake/create-fails", AgentHandler.create_fails),
    ("POST", r"/fake/gpu-usage", AgentHandler.gpu_usage),
    ("GET", rf"/fake/workloads/(?P<id>{ID_PATTERN})/ssh-keys", AgentHandler.show_ssh_keys),
    ("POST", r"/fake/ssh-sshd", AgentHandler.set_sshd),
    ("POST", r"/fake/ssh-install", AgentHandler.set_ssh_install),
    ("POST", r"/fake/app-install", AgentHandler.set_app_install),
    ("GET", rf"/fake/workloads/(?P<id>{ID_PATTERN})/apps", AgentHandler.show_apps),
]


def make_server(engine, token, host="127.0.0.1", port=0, stats=None):
    handler = type("BoundHandler", (AgentHandler,), {"engine": engine, "token": token.encode(), "consoles": Consoles(), "stats": stats or FakeStats()})
    return ThreadingHTTPServer((host, port), handler)
