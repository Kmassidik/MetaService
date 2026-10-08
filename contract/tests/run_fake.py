"""Start the Fake Agent on a free port, run every conformance check against it, then stop it."""
import secrets
import sys
import threading

from agent.fake.engine import FakeEngine
from agent.fake.server import make_server
from contract.tests.runner import run_checks


def main():
    token = secrets.token_hex(24)
    server = make_server(FakeEngine(), token)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        failures = run_checks(f"http://127.0.0.1:{server.server_address[1]}", token)
    finally:
        server.shutdown()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
