"""Helpers for checks that start a real macOS Agent (and sometimes a real Root next to it)."""
import json
import os
import pathlib
import secrets
import subprocess
import tempfile
import time
from contextlib import contextmanager

from contract.root_tests.support import CheckFailed, expect, _free_port, _port_open

BINARY = pathlib.Path(__file__).resolve().parents[2] / "agent" / "macos" / ".build" / "debug" / "metaservice-agent"
START_WAIT_SECONDS = 20


def write_secret(path, text, mode=0o600):
    pathlib.Path(path).write_text(text)
    os.chmod(path, mode)


class RunningAgent:
    def __init__(self, token=None, token_mode=0o600, extra=None, with_token=True):
        self.state = tempfile.mkdtemp(prefix="ms-agent-")
        self.token = token or secrets.token_hex(24)
        self.port = _free_port()
        self.url = f"http://127.0.0.1:{self.port}"
        self.extra = extra or []
        self.process = None
        if with_token:
            write_secret(os.path.join(self.state, "agent.token"), self.token, token_mode)

    def start(self):
        args = [str(BINARY), "run", "--state-dir", self.state, "--port", str(self.port), "--bind", "127.0.0.1", "--engine", "simulated"] + self.extra
        self.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.early_exit = (None, "")
        deadline = time.time() + START_WAIT_SECONDS
        while time.time() < deadline:
            if self.process.poll() is not None:
                self.early_exit = (self.process.returncode, self.process.stderr.read().decode())
                raise CheckFailed(f"the Agent exited early: {self.early_exit[1][:200]}")
            if _port_open(self.port):
                return self
            time.sleep(0.1)
        raise CheckFailed("the Agent did not start in time")

    def stop(self):
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.process.wait(timeout=5)

    def call(self, method, path, body=None, token="default", headers=None):
        import http.client
        sent = dict(headers or {})
        use = self.token if token == "default" else token
        if use is not None:
            sent["Authorization"] = f"Bearer {use}"
        data = None if body is None else json.dumps(body).encode()
        if data is not None:
            sent["Content-Type"] = "application/json"
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)
        connection.request(method, path, body=data, headers=sent)
        response = connection.getresponse()
        raw = response.read()
        connection.close()
        return response.status, (json.loads(raw) if raw else None)


@contextmanager
def agent(**kwargs):
    running = RunningAgent(**kwargs).start()
    try:
        yield running
    finally:
        running.stop()


def run_cli(args, env=None):
    """Run the Agent's command line once. Returns (exit code, stdout, stderr)."""
    done = subprocess.run([str(BINARY)] + args, capture_output=True, text=True, timeout=30, env={**os.environ, **(env or {})})
    return done.returncode, done.stdout, done.stderr


def wait_for(condition, seconds, message):
    deadline = time.time() + seconds
    while time.time() < deadline:
        found = condition()
        if found:
            return found
        time.sleep(0.3)
    raise CheckFailed(message)
