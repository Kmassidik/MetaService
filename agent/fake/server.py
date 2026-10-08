"""HTTP front of the Fake Agent. Implements the Agent half of contract/openapi.yaml."""
import hmac
import itertools
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from agent.fake.engine import NotFound, Refused
from contract import spec

MAX_BODY_BYTES = 64 * 1024
MAX_DRAIN_BYTES = 1024 * 1024
ID_PATTERN = r"[a-z0-9][a-z0-9-]{0,62}"
JSON_TYPE = "application/json"


class ApiError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status, self.code, self.message = status, code, message


class AgentHandler(BaseHTTPRequestHandler):
    engine = None
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

    def do_DELETE(self):
        self._serve("DELETE")

    def _serve(self, method):
        try:
            self._require_token()
            handler, params = self._route(method)
            handler(self, **params)
        except ApiError as error:
            self._send(error.status, {"error": {"code": error.code, "message": error.message}})
        except Refused as refused:
            self._send(409, {"error": {"code": refused.code, "message": refused.message, "resource": refused.resource,
                                       "needed": refused.needed, "free": refused.free}})
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

    def _body(self, schema_name):
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
            raise ApiError(400, "invalid_input", "; ".join(found))
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

    def list_workloads(self):
        self._send(200, {"workloads": self.engine.workloads()})

    def create_workload(self):
        record = self.engine.create(self._body("WorkloadCreate"))
        self._send(202, _accepted(record))

    def start_workload(self, id):
        self._send(202, _accepted(self.engine.set_state(self._command_id(), id, "start", "running")))

    def stop_workload(self, id):
        self._send(202, _accepted(self.engine.set_state(self._command_id(), id, "stop", "stopped")))

    def delete_workload(self, id):
        self._send(202, _accepted(self.engine.delete(self._command_id(), id)))

    def install_bundle(self):
        self._send(202, _accepted(self.engine.install_bundle(self._body("BundleInstall"))))

    def get_command(self, id):
        self._send(200, self.engine.command(id))


def _accepted(record):
    return {"command_id": record["command_id"], "state": record["state"]}


ROUTES = [
    ("GET", r"/v1/health", AgentHandler.health),
    ("GET", r"/v1/facts", AgentHandler.facts),
    ("GET", r"/v1/workloads", AgentHandler.list_workloads),
    ("POST", r"/v1/workloads", AgentHandler.create_workload),
    ("POST", rf"/v1/workloads/(?P<id>{ID_PATTERN})/start", AgentHandler.start_workload),
    ("POST", rf"/v1/workloads/(?P<id>{ID_PATTERN})/stop", AgentHandler.stop_workload),
    ("DELETE", rf"/v1/workloads/(?P<id>{ID_PATTERN})", AgentHandler.delete_workload),
    ("POST", r"/v1/bundle/install", AgentHandler.install_bundle),
    ("GET", rf"/v1/commands/(?P<id>{ID_PATTERN})", AgentHandler.get_command),
]


def make_server(engine, token, host="127.0.0.1", port=0):
    handler = type("BoundHandler", (AgentHandler,), {"engine": engine, "token": token.encode()})
    return ThreadingHTTPServer((host, port), handler)
