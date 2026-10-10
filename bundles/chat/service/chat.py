#!/usr/bin/env python3
"""MetaService chat service v0. Runs on every machine and workload that has the chat bundle.

Standard library only, so the same file runs on macOS and Linux with no install step beyond Python 3.
Every API call needs the access key (Authorization: Bearer ...). The page itself holds no secrets.
With --brain-url the replies come from the AI through the Root's proxy (see brain.py); without it, or while the Root has no AI set up,
the chat answers with a plain message that says so.
"""
import argparse
import hmac
import json
import os
import pathlib
import signal
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import brain as brain_client  # noqa: E402

MAX_BODY_BYTES = 16 * 1024
MAX_MESSAGE_CHARS = 4000
MESSAGES_PER_MINUTE = 30
KEY_MIN_LENGTH = 32
CSP = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml"}
PAGES = {"/": "index.html", "/chat.js": "chat.js", "/chat.css": "chat.css", "/theme-init.js": "theme-init.js", "/ruvio-mark.svg": "ruvio-mark.svg"}


class Limiter:
    """At most `limit` hits per minute, counted from the first hit in the window."""

    def __init__(self, limit, clock=time.monotonic):
        self.limit, self.clock = limit, clock
        self.lock = threading.Lock()
        self.window_start, self.count = clock(), 0

    def allow(self):
        with self.lock:
            now = self.clock()
            if now - self.window_start >= 60:
                self.window_start, self.count = now, 0
            if self.count >= self.limit:
                return False
            self.count += 1
            return True


def read_key(path):
    """The access key: a file that only its owner can read, holding at least 32 characters."""
    mode = os.stat(path).st_mode & 0o777
    if mode & 0o077:
        raise SystemExit(f"{path} must be mode 600 (owner only)")
    key = pathlib.Path(path).read_text().strip()
    if len(key) < KEY_MIN_LENGTH:
        raise SystemExit(f"the access key in {path} is too short")
    return key


def check_message(raw):
    """The message text from a request body, or None if the body is not a valid message."""
    try:
        body = json.loads(raw)
    except ValueError:
        return None
    if not isinstance(body, dict) or set(body) != {"message"} or not isinstance(body["message"], str):
        return None
    text = body["message"].strip()
    return text if 0 < len(text) <= MAX_MESSAGE_CHARS else None


def answer(message, version, host):
    """v0 reply. Plain text only; the page shows it as text, never as HTML."""
    return f"Chat {version} is running on {host}. The AI is not connected yet, so all I can do is repeat you: {message}"


def reply_to(message, brain, version, host):
    """The AI's answer through the Root, or the plain v0 message when there is no brain or the Root has none set up."""
    if brain is None:
        return 200, answer(message, version, host)
    try:
        return 200, brain.reply(message)
    except brain_client.BrainNotConfigured:
        return 200, answer(message, version, host)
    except brain_client.BrainUnavailable as problem:
        return 502, str(problem)


def make_handler(key, web_dir, version, host, brain=None):
    limiter = Limiter(MESSAGES_PER_MINUTE)

    class Handler(BaseHTTPRequestHandler):
        server_version = "MetaServiceChat"

        def log_message(self, *args):
            return

        def _send(self, status, payload=b"", content_type="application/json", extra=None):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Content-Security-Policy", CSP)
            for name, value in (extra or {}).items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(payload)

        def _json(self, status, body):
            self._send(status, json.dumps(body).encode())

        def _error(self, status, code, message):
            self._json(status, {"error": {"code": code, "message": message}})

        def _authorized(self):
            sent = self.headers.get("Authorization", "")
            return sent.startswith("Bearer ") and hmac.compare_digest(sent[7:].encode(), key.encode())

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/health":
                return self._json(200, {"status": "ok", "version": version})
            name = PAGES.get(path)
            if name is None:
                return self._error(404, "not_found", "no such page")
            file = pathlib.Path(web_dir) / name
            self._send(200, file.read_bytes(), TYPES[file.suffix])

        def do_POST(self):
            if self.path.split("?", 1)[0] != "/api/chat":
                return self._error(404, "not_found", "no such thing")
            if not self._authorized():
                return self._error(401, "unauthorized", "missing or wrong access key")
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length > MAX_BODY_BYTES:
                self.rfile.read(min(length, 1024 * 1024))
                return self._error(413, "too_large", "message too large")
            message = check_message(self.rfile.read(length))
            if message is None:
                return self._error(400, "invalid_input", "send {\"message\": \"text\"} with up to 4000 characters")
            if not limiter.allow():
                return self._error(429, "rate_limited", "slow down")
            status, text = reply_to(message, brain, version, host)
            if status != 200:
                return self._error(status, "brain_unavailable", text)
            self._json(200, {"reply": text})

        def do_PUT(self):
            self._error(404, "not_found", "no such thing")

        do_DELETE = do_PATCH = do_PUT

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description="MetaService chat service")
    parser.add_argument("--port", type=int, default=9200)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--web-dir", default=str(pathlib.Path(__file__).resolve().parent.parent / "web"))
    parser.add_argument("--brain-url", help="address of the Root; replies then come from the AI through its proxy")
    parser.add_argument("--version", default=(pathlib.Path(__file__).resolve().parent.parent / "VERSION").read_text().strip())
    args = parser.parse_args(argv)
    # A parent that ignores these signals passes that on to its children; chat must still stop when asked to.
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    key = read_key(args.key_file)
    brain = brain_client.Brain(args.brain_url, key) if args.brain_url else None
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(key, args.web_dir, args.version, socket.gethostname(), brain))
    print(f"chat {args.version} on {args.bind}:{server.server_address[1]}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
