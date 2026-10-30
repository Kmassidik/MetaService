"""A stand-in for the join-share hub's admin listener. Needs the right X-Admin-Key, records every request it receives.

Steering: approving pending id `wrong` answers 403 wrong_code with tries_left 2; `leak` answers a body that holds the key; `html` answers non-JSON;
peer `taken` answers 409. Everything else answers a small fixed JSON.
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def make_hub(key, host="127.0.0.1"):
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            return

        def _handle(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0") or 0))
            sent_key = self.headers.get("X-Admin-Key")
            calls.append({"method": self.command, "path": self.path, "key": sent_key, "body": raw, "content_type": self.headers.get("Content-Type")})
            if sent_key != key:
                return self._send(401, {"error": "bad_key"})
            if self.path.endswith("/wrong/approve"):
                return self._send(403, {"error": "wrong_code", "tries_left": 2})
            if self.path.endswith("/leak/approve"):
                return self._send(200, {"echo": sent_key})
            if self.path.endswith("/html/approve"):
                return self._send(200, None, raw=b"<html>nope</html>")
            if self.path.endswith("/peers/taken"):
                return self._send(409, {"error": "name_taken"})
            if self.path == "/admin/supported":
                return self._send(200, [{"os": "mac", "cpus": [{"cpu": "arm64", "state": "ready"}]}])
            self._send(200, {"ok": True, "path": self.path})

        do_GET = do_POST = do_DELETE = _handle

        def _send(self, status, payload, raw=None):
            raw = raw if raw is not None else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    server = ThreadingHTTPServer((host, 0), Handler)
    server.calls = calls
    server.base_url = f"http://{host}:{server.server_address[1]}"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
