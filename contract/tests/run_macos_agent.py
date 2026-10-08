"""Run every conformance check against the real macOS Agent (simulated engine), started on a free port with a throwaway token."""
import os
import pathlib
import secrets
import socket
import subprocess
import sys
import tempfile
import time

from contract.tests.runner import run_checks

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
    state = tempfile.mkdtemp(prefix="ms-agent-")
    token = secrets.token_hex(24)
    token_file = os.path.join(state, "agent.token")
    pathlib.Path(token_file).write_text(token)
    os.chmod(token_file, 0o600)
    port = free_port()
    process = subprocess.Popen([str(BINARY), "run", "--state-dir", state, "--port", str(port), "--bind", "127.0.0.1", "--engine", "simulated"] + BUDGET_ARGS,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        wait_until_up(port, process)
        failures = run_checks(f"http://127.0.0.1:{port}", token)
    finally:
        process.terminate()
        process.wait(timeout=5)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
