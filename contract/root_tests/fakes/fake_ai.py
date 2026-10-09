"""A stand-in for an OpenAI-style AI provider. Needs the right Bearer key, records every request it receives.

Steering by the message text: BREAK answers 500, BOUNCE answers a redirect, anything else is echoed back with fixed token counts.
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROMPT_TOKENS, COMPLETION_TOKENS = 11, 7


def make_ai(key, host="127.0.0.1"):
    calls = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            return

        def do_POST(self):
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0") or 0))
            body = json.loads(raw or b"{}")
            calls.append({"path": self.path, "authorization": self.headers.get("Authorization"), "body": body})
            if self.path != "/v1/chat/completions" or self.headers.get("Authorization") != f"Bearer {key}":
                return self._send(401, {"error": "bad key"})
            message = body["messages"][-1]["content"]
            if "BREAK" in message:
                return self._send(500, {"error": "secret provider detail " + key})
            if "BOUNCE" in message:
                self.send_response(307)
                self.send_header("Location", "http://127.0.0.1:1/elsewhere")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            reply = {"choices": [{"message": {"role": "assistant", "content": "echo: " + message}}],
                     "usage": {"prompt_tokens": PROMPT_TOKENS, "completion_tokens": COMPLETION_TOKENS}}
            self._send(200, reply)

        def _send(self, status, payload):
            raw = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    server = ThreadingHTTPServer((host, 0), Handler)
    server.calls = calls
    server.base_url = f"http://{host}:{server.server_address[1]}/v1"
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
