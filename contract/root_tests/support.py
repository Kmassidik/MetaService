"""Helpers for the Root black-box tests: start a real Root, talk to it with cookies, no redirects followed."""
import http.client
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time
from contextlib import contextmanager

REPO = pathlib.Path(__file__).resolve().parents[2]
PACKAGE = REPO / "root" / "macos"
FAKE_BINARY = PACKAGE / ".build-fake" / "debug" / "metaservice-root"
PLAIN_BINARY = PACKAGE / ".build" / "debug" / "metaservice-root"
ALLOWED_EMAIL = "kurnia@example.com"
START_WAIT_SECONDS = 15


class CheckFailed(AssertionError):
    pass


def expect(condition, message):
    if not condition:
        raise CheckFailed(message)


class Reply:
    def __init__(self, status, headers, raw):
        self.status, self.headers, self.raw = status, headers, raw
        self.cookies = [value for name, value in headers if name.lower() == "set-cookie"]
        try:
            self.body = json.loads(raw) if raw else None
        except ValueError:
            self.body = None

    def header(self, name):
        return next((value for key, value in self.headers if key.lower() == name.lower()), None)


class RunningRoot:
    """A real Root process with its own database and env file, stopped when the check ends."""

    def __init__(self, binary=FAKE_BINARY, env_text=None, env_mode=0o600):
        self.binary = binary
        self.dir = tempfile.mkdtemp(prefix="ms-root-")
        self.port = _free_port()
        self.base = f"http://localhost:{self.port}"
        env = env_text if env_text is not None else f"ALLOWED_EMAILS={ALLOWED_EMAIL}\n"
        self.env_file = os.path.join(self.dir, "root.env")
        pathlib.Path(self.env_file).write_text(env)
        os.chmod(self.env_file, env_mode)
        self.process = None
        self.early_exit = (None, "")

    def start(self):
        args = [str(self.binary), "--env-file", self.env_file, "--db", os.path.join(self.dir, "root.sqlite3"),
                "--port", str(self.port), "--bind", "127.0.0.1", "--public-url", self.base]
        self.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self._wait_until_up()
        return self

    def _wait_until_up(self):
        deadline = time.time() + START_WAIT_SECONDS
        while time.time() < deadline:
            if self.process.poll() is not None:
                self.early_exit = (self.process.returncode, self.process.stderr.read().decode())
                raise CheckFailed(f"Root exited early: {self.early_exit[1][:300]}")
            if _port_open(self.port):
                return
            time.sleep(0.05)
        raise CheckFailed("Root did not start in time")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)

    def exit_text(self):
        return self.early_exit


class Browser:
    """One HTTP client with its own cookies. Never follows redirects."""

    def __init__(self, root):
        self.root = root
        self.cookies = {}

    def request(self, method, path, body=None, headers=None, raw=None, origin="default", cookies=True):
        data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
        sent = dict(headers or {})
        if origin == "default" and method != "GET":
            sent["Origin"] = self.root.base
        elif origin not in ("default", None):
            sent["Origin"] = origin
        if cookies and self.cookies and "Cookie" not in sent:
            sent["Cookie"] = "; ".join(f"{k}={v}" for k, v in self.cookies.items())
        if data is not None:
            sent.setdefault("Content-Type", "application/json")
        connection = http.client.HTTPConnection("127.0.0.1", self.root.port, timeout=15)
        connection.request(method, path, body=data, headers=sent)
        response = connection.getresponse()
        reply = Reply(response.status, response.getheaders(), response.read())
        connection.close()
        self._remember(reply)
        return reply

    def _remember(self, reply):
        for line in reply.cookies:
            name, _, rest = line.partition("=")
            value = rest.split(";", 1)[0]
            if "Max-Age=0" in line:
                self.cookies.pop(name, None)
            else:
                self.cookies[name] = value

    def sign_in(self, email=ALLOWED_EMAIL):
        reply = self.request("POST", "/auth/fake", {"email": email})
        expect(reply.status == 302, f"fake sign-in gave {reply.status}: {reply.raw[:120]!r}")
        return reply

    def csrf(self):
        reply = self.request("GET", "/api/session")
        expect(reply.status == 200, f"/api/session gave {reply.status}")
        return reply.body["csrf_token"]

    def write(self, method, path, body=None, **kwargs):
        headers = dict(kwargs.pop("headers", {}))
        headers["X-CSRF-Token"] = self.csrf()
        return self.request(method, path, body, headers=headers, **kwargs)


def _free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def _port_open(port):
    with socket.socket() as sock:
        sock.settimeout(0.2)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def raw_exchange(root, payload, wait=3.0):
    """Send raw bytes and return what comes back (or b'' if the server just closes)."""
    with socket.create_connection(("127.0.0.1", root.port), timeout=wait) as sock:
        sock.sendall(payload)
        chunks = []
        try:
            while True:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                chunks.append(chunk)
        except (socket.timeout, ConnectionResetError):
            pass
        return b"".join(chunks)


@contextmanager
def running(**kwargs):
    root = RunningRoot(**kwargs).start()
    try:
        yield root
    finally:
        root.stop()


def enrolled_machine(browser, name="mini"):
    """Sign in, invite a machine, enroll it as an Agent would. Returns the machine token."""
    browser.sign_in()
    invite = browser.write("POST", "/api/enrollments", {"name": name})
    expect(invite.status == 201, f"invite gave {invite.status}: {invite.raw[:120]!r}")
    reply = Browser(browser.root).request("POST", "/v1/agents/enroll", {"enrollment_token": invite.body["enrollment_token"], "name": name}, origin=None)
    expect(reply.status == 200, f"enroll gave {reply.status}: {reply.raw[:120]!r}")
    return reply.body["machine_token"]


def good_heartbeat(**changes):
    body = {
        "facts": {"os": "linux", "arch": "aarch64", "cpu_cores": 20, "ram_total_mb": 131072, "disk_total_gb": 3800,
                  "free_ram_mb": 100000, "free_disk_gb": 3000, "gpu": [{"vendor": "nvidia", "model": "GB10", "memory_mb": 131072}],
                  "capabilities": {"vm": True, "container": True, "gpu_in_vm": False, "gpu_in_container": True}},
        "workloads": [{"id": "wl-1", "name": "demo", "kind": "container", "state": "running", "cpu": 2, "ram_mb": 2048,
                       "disk_gb": 20, "gpu_mode": "container", "address": None, "bundle_version": "1.0.0"}],
        "bundle_version": "1.0.0",
    }
    body.update(changes)
    return body
