#!/usr/bin/env python3
"""MetaService chat service. Runs on every machine and workload that has the chat bundle.

Standard library only, so the same file runs on macOS and Linux with no install step beyond Python 3.
It serves the Ruvio chat screen (the same screen as the Ruvio chat) and the routes that screen calls, for one owner: whoever opens it with this
machine's access key. The screen's data lives in one SQLite file next to the key. The AI is reached only through the Root's proxy (see brain.py).
Without --brain-url, or while the Root has no AI set up, replies are a plain message that says so.
"""
import argparse
import hashlib
import hmac
import json
import os
import pathlib
import signal
import socket
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import brain as brain_client  # noqa: E402
from replies import reply_to  # noqa: E402
from ruvio import api as ruvio_api  # noqa: E402
from ruvio import sessions as ruvio_sessions  # noqa: E402
from ruvio.runner import Runner  # noqa: E402
from ruvio.store import Store  # noqa: E402

MAX_BODY_BYTES = 16 * 1024
MAX_MESSAGE_CHARS = 4000
MESSAGES_PER_MINUTE = 30
KEY_MIN_LENGTH = 32
CSP = ("default-src 'none'; script-src 'self'; worker-src 'self' blob:; style-src 'self'; img-src 'self' data: blob:; font-src 'self'; "
       "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
TYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
         ".svg": "image/svg+xml", ".png": "image/png", ".webp": "image/webp", ".json": "application/json", ".woff2": "font/woff2"}
ENTRY, OPEN_PAGE = "index.html", "open.html"
OWNER_NAME = "You"
LONG_CACHE = "public, max-age=31536000, immutable"


def utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


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


def safe_file(web_dir, url_path):
    """The file inside web_dir that a URL path names, or None: nothing outside the folder, no hidden names, no directories."""
    parts = [part for part in url_path.split("/") if part]
    if not parts or any(part.startswith(".") or "\\" in part or "%" in part for part in parts):
        return None
    candidate = pathlib.Path(web_dir, *parts)
    return candidate if candidate.is_file() and candidate.resolve().is_relative_to(pathlib.Path(web_dir).resolve()) else None


def make_app(data_dir, version, host, brain):
    """The Ruvio chat's shared parts for this machine: its store, its runner and who owns it."""
    pathlib.Path(data_dir).mkdir(mode=0o700, parents=True, exist_ok=True)
    store = Store(str(pathlib.Path(data_dir) / "chat.sqlite3"), utc_now)
    store.interrupt_open_runs()
    owner = {"id": hashlib.sha256(host.encode()).hexdigest(), "name": OWNER_NAME, "email": f"owner@{host}"}
    app = ruvio_api.App(store, Runner(store, brain, version, host), owner, host, utc_now())
    if not store.agents():
        app.welcome(store.create_agent("Ruvio", "Your assistant on this machine.", ruvio_api.DEFAULT_SHAPE, ruvio_api.DEFAULT_COLOR))
    return app


def make_handler(key, web_dir, version, host, brain=None, app=None):
    limiter = Limiter(MESSAGES_PER_MINUTE)
    sessions = ruvio_sessions.Sessions(key)

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

        def _json(self, status, body, extra=None):
            self._send(status, json.dumps(body).encode(), extra=extra)

        def _error(self, status, code, message):
            self._json(status, {"error": {"code": code, "message": message}})

        def _authorized(self):
            sent = self.headers.get("Authorization", "")
            return sent.startswith("Bearer ") and hmac.compare_digest(sent[7:].encode(), key.encode())

        def _session(self):
            return sessions.find(self.headers.get("Cookie", ""))

        def _page(self, name):
            self._send(200, pathlib.Path(web_dir, name).read_bytes(), TYPES[".html"])

        def _read_body(self):
            """The request body, or None after the error reply when it is too large."""
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length > MAX_BODY_BYTES:
                self.rfile.read(min(length, 1024 * 1024))
                self._error(413, "too_large", "message too large")
                return None
            return self.rfile.read(length)

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/health":
                return self._json(200, {"status": "ok", "version": version})
            if path.startswith("/api/"):
                return self._api("GET")
            if path == "/":
                return self._page(ENTRY if self._session() else OPEN_PAGE)
            self._asset(path)

        def _asset(self, path):
            file = safe_file(web_dir, path)
            if file is None or file.name in (ENTRY, "VERSION"):
                return self._error(404, "not_found", "no such page")
            cache = {"Cache-Control": LONG_CACHE} if "/assets/" in path else None
            self._send(200, file.read_bytes(), TYPES.get(file.suffix, "application/octet-stream"), cache)

        def do_POST(self):
            path = urlsplit(self.path).path
            if path == "/api/chat":
                return self._simple_chat()
            if path == "/auth/open":
                return self._open_session()
            if path == "/auth/logout":
                return self._close_session()
            if path.startswith("/api/"):
                return self._api("POST")
            self._error(404, "not_found", "no such thing")

        def do_PATCH(self):
            self._api_only("PATCH")

        def do_DELETE(self):
            self._api_only("DELETE")

        def _api_only(self, method):
            if not self.path.startswith("/api/"):
                return self._error(404, "not_found", "no such thing")
            self._api(method)

        def do_PUT(self):
            self._error(404, "not_found", "no such thing")

        def _open_session(self):
            if not self._authorized():
                return self._error(401, "unauthorized", "missing or wrong access key")
            session = sessions.open(key)
            self._json(200, {"ok": True}, {"Set-Cookie": ruvio_sessions.set_cookie(session)})

        def _close_session(self):
            session = self._session()
            if session is not None:
                sessions.close(session)
            self._json(200, {"ok": True}, {"Set-Cookie": ruvio_sessions.clear_cookie()})

        def _simple_chat(self):
            """The plain API: one message in, one reply out, with the access key as a Bearer token."""
            if not self._authorized():
                return self._error(401, "unauthorized", "missing or wrong access key")
            raw = self._read_body()
            if raw is None:
                return None
            message = check_message(raw)
            if message is None:
                return self._error(400, "invalid_input", "send {\"message\": \"text\"} with up to 4000 characters")
            if not limiter.allow():
                return self._error(429, "rate_limited", "slow down")
            status, text = reply_to(message, brain, version, host)
            if status != 200:
                return self._error(status, "brain_unavailable", text)
            self._json(200, {"reply": text})

        def _api(self, method):
            parts = urlsplit(self.path)
            found = ruvio_api.route(method, parts.path)
            if app is None or found is None:
                return self._json(*ruvio_api.NOT_FOUND)
            handler, match, needs_session = found
            session = self._session()
            if needs_session and session is None:
                return self._json(401, {"error": "Sign in again by opening the chat from the MetaService panel."})
            if method in ruvio_api.MUTATING and not self._same_origin_and_csrf(session):
                return self._json(403, {"error": "That request was refused."})
            raw = self._read_body() if method in ruvio_api.MUTATING else b""
            if raw is None:
                return None
            body = self._json_body(raw)
            if body is None:
                return self._json(400, {"error": "The request was not valid JSON."})
            call = ruvio_api.Call(method, parts.path, parse_qs(parts.query), body, session, app)
            call.match = match
            self._json(*handler(call))

        def _same_origin_and_csrf(self, session):
            origin = self.headers.get("Origin")
            same = origin is None or urlsplit(origin).netloc == self.headers.get("Host")
            token = self.headers.get("X-CSRF-Token", "")
            return same and session is not None and hmac.compare_digest(token.encode(), session.csrf.encode())

        @staticmethod
        def _json_body(raw):
            if not raw:
                return {}
            try:
                body = json.loads(raw)
            except ValueError:
                return None
            return body if isinstance(body, dict) else None

    return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description="MetaService chat service")
    parser.add_argument("--port", type=int, default=9200)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--data-dir", help="where the conversations are kept (default: chat-data next to the key file)")
    parser.add_argument("--web-dir", default=str(pathlib.Path(__file__).resolve().parent.parent / "web"))
    parser.add_argument("--brain-url", help="address of the Root; replies then come from the AI through its proxy")
    parser.add_argument("--version", default=(pathlib.Path(__file__).resolve().parent.parent / "VERSION").read_text().strip())
    args = parser.parse_args(argv)
    # A parent that ignores these signals passes that on to its children; chat must still stop when asked to.
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    key = read_key(args.key_file)
    brain = brain_client.Brain(args.brain_url, key) if args.brain_url else None
    host = socket.gethostname()
    data_dir = args.data_dir or str(pathlib.Path(args.key_file).resolve().parent / "chat-data")
    app = make_app(data_dir, args.version, host, brain)
    server = ThreadingHTTPServer((args.bind, args.port), make_handler(key, args.web_dir, args.version, host, brain, app))
    print(f"chat {args.version} on {args.bind}:{server.server_address[1]}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
