"""A pretend Cloudflare for tests: the few calls the remote-access tool makes, kept in memory. Nothing real is ever contacted."""
import json
import re
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = "tok_SECRET_value_that_must_never_be_printed_0123456789"
TUNNEL_TOKEN = "tunnel_SECRET_token_that_must_stay_in_its_file_9876543210"
ACCOUNT = "a" * 32
ZONE = "b" * 32


class World:
    def __init__(self):
        self.zone_name = "example.com"
        self.tunnels = {}
        self.dns = []
        self.configs = {}
        self.connected = set()
        self.calls = []
        self.fail = {}          # "METHOD path-fragment" -> http status to answer instead
        self.user_token = True  # False: only the account-owned token check works
        self.token_active = True
        self.echo_token_in_errors = False  # a careless server that repeats the token it was sent

    def writes(self):
        return [call for call in self.calls if call.split(" ")[0] != "GET"]


def _reply(handler, status, success, result=None, message=""):
    body = json.dumps({"success": success, "result": result, "errors": [] if success else [{"message": message}]}).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def make_handler(world):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _route(self, method):
            parts = urlparse(self.path)
            path, query = parts.path, parse_qs(parts.query)
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length)) if length else None
            world.calls.append(f"{method} {path}")
            if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                return _reply(self, 401, False, message="Invalid API token")
            for key, status in world.fail.items():
                verb, _, fragment = key.partition(" ")
                if verb == method and fragment in path:
                    echoed = " " + TOKEN if world.echo_token_in_errors else ""
                    return _reply(self, status, False, message="forced failure" + echoed)
            return self._dispatch(method, path, query, body)

        def _dispatch(self, method, path, query, body):
            if path == "/user/tokens/verify":
                ok = world.user_token and world.token_active
                return _reply(self, 200 if ok else 400, ok, {"status": "active"} if ok else None, "not a user token")
            if path == f"/accounts/{ACCOUNT}/tokens/verify":
                return _reply(self, 200, True, {"status": "active" if world.token_active else "disabled"})
            if path == f"/zones/{ZONE}":
                return _reply(self, 200, True, {"name": world.zone_name})
            if path.startswith(f"/zones/{ZONE}/dns_records"):
                return self._dns(method, path, query, body)
            if path.startswith(f"/accounts/{ACCOUNT}/cfd_tunnel"):
                return self._tunnel(method, path, query, body)
            return _reply(self, 404, False, message="unknown path")

        def _dns(self, method, path, query, body):
            if method == "GET":
                found = [r for r in world.dns if r["name"] == query.get("name", [""])[0]]
                return _reply(self, 200, True, found)
            if method == "POST":
                record = dict(body, id=uuid.uuid4().hex)
                world.dns.append(record)
                return _reply(self, 200, True, record)
            record_id = path.rsplit("/", 1)[1]
            world.dns = [r for r in world.dns if r["id"] != record_id]
            return _reply(self, 200, True, {"id": record_id})

        def _tunnel(self, method, path, query, body):
            rest = path[len(f"/accounts/{ACCOUNT}/cfd_tunnel"):].strip("/")
            if not rest:
                return self._tunnels_root(method, query, body)
            tunnel_id, _, tail = rest.partition("/")
            if tunnel_id not in world.tunnels:
                return _reply(self, 404, False, message="tunnel not found")
            return self._one_tunnel(method, tunnel_id, tail, body)

        def _tunnels_root(self, method, query, body):
            if method == "GET":
                name = query.get("name", [""])[0]
                return _reply(self, 200, True, [t for t in world.tunnels.values() if t["name"] == name])
            tunnel = {"id": uuid.uuid4().hex, "name": body["name"], "config_src": body.get("config_src")}
            world.tunnels[tunnel["id"]] = tunnel
            return _reply(self, 200, True, tunnel)

        def _one_tunnel(self, method, tunnel_id, tail, body):
            if tail == "configurations" and method == "PUT":
                world.configs[tunnel_id] = body
                return _reply(self, 200, True, {})
            if tail == "token":
                return _reply(self, 200, True, TUNNEL_TOKEN)
            if tail == "connections":
                world.connected.discard(tunnel_id)
                return _reply(self, 200, True, {})
            if method == "DELETE":
                if tunnel_id in world.connected:
                    return _reply(self, 400, False, message="tunnel has active connections")
                del world.tunnels[tunnel_id]
                return _reply(self, 200, True, {"id": tunnel_id})
            shown = dict(world.tunnels[tunnel_id], connections=[{"id": "c1"}] if tunnel_id in world.connected else [])
            return _reply(self, 200, True, shown)

        def do_GET(self):
            self._route("GET")

        def do_POST(self):
            self._route("POST")

        def do_PUT(self):
            self._route("PUT")

        def do_DELETE(self):
            self._route("DELETE")

    return Handler


class FakeServer:
    def __init__(self):
        self.world = World()
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.world))
        self.base = f"http://127.0.0.1:{self._server.server_address[1]}"
        threading.Thread(target=self._server.serve_forever, daemon=True).start()

    def stop(self):
        self._server.shutdown()
        self._server.server_close()
