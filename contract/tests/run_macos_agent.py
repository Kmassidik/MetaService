"""Run every conformance check against the real macOS Agent, started on a free port with a throwaway token.
With --apple the Agent drives a fake `container` program through the Apple engine; otherwise it uses the simulated engine."""
import os
import pathlib
import secrets
import socket
import subprocess
import sys
import tempfile
import time

from contract.agent_tests.support import FakeContainerWorld
from contract.tests.bundle_source import BundleSource
from contract.tests.runner import run_checks
from contract.tests.support import Bundles

BINARY = pathlib.Path(__file__).resolve().parents[2] / "agent" / "macos" / ".build" / "debug" / "metaservice-agent"
START_WAIT_SECONDS = 20
# Allowances keep the budget smaller than the real machine, so the checks about free space behave the same on any Mac.
BUDGET_ARGS = ["--ram-allowance-mb", "16384", "--ram-reserve-mb", "4096", "--disk-allowance-gb", "200", "--disk-reserve-gb", "10",
               # The suite sends many wrong tokens on purpose; the lockout itself is checked separately.
               "--bad-token-limit", "100000"]


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_until_up(port, process):
    deadline = time.time() + START_WAIT_SECONDS
    while time.time() < deadline:
        if process.poll() is not None:
            raise SystemExit(f"the Agent exited early: {process.stderr.read().decode()[:300]}")
        with socket.socket() as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    raise SystemExit("the Agent did not start in time")


def main():
    engine = "apple" if "--apple" in sys.argv else "simulated"
    state = tempfile.mkdtemp(prefix="ms-agent-")
    token = secrets.token_hex(24)
    token_file = os.path.join(state, "command.token")
    pathlib.Path(token_file).write_text(token)
    os.chmod(token_file, 0o600)
    machine_token = secrets.token_hex(24)
    source = BundleSource(machine_token)
    for name, text in (("agent.token", machine_token), ("agent.json", f'{{"root": "{source.url}", "name": "conformance"}}')):
        pathlib.Path(state, name).write_text(text)
        os.chmod(pathlib.Path(state, name), 0o600)
    port = free_port()
    extra, env = [], os.environ.copy()
    if engine == "apple":
        world = FakeContainerWorld()
        extra, env = world.agent_args(), {**os.environ, **world.env}
    process = subprocess.Popen([str(BINARY), "run", "--state-dir", state, "--port", str(port), "--bind", "127.0.0.1", "--engine", engine, "--chat-port", str(free_port())] + extra + BUDGET_ARGS,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        wait_until_up(port, process)
        failures = run_checks(f"http://127.0.0.1:{port}", token, bundle=Bundles(source.versions, source.sha, verifies=True))
    finally:
        source.stop()
        process.terminate()
        process.wait(timeout=5)
    if failures:
        log = os.path.join(state, "chat.log")
        print(f"\nAgent state kept in {state}\nchat.log: {open(log).read()[-500:] if os.path.exists(log) else '(none)'}\nAgent stderr: {process.stderr.read().decode()[-500:]}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
