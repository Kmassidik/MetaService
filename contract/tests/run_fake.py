"""Start the Fake Agent on a free port, run every conformance check against it, then stop it."""
import secrets
import sys
import threading

from agent.fake.engine import CPU_OPTIONS, FakeEngine, MachineSpec
from agent.fake.server import make_server
from contract.tests.runner import run_checks


# A machine with a card containers can share and the CPU settings of a helper of this build, so the GPU memory limit and the CPU options are exercised too.
# The mutation run uses a plain machine, so the same checks also meet a helper that offers neither.
GPU_AND_CPU_SPEC = MachineSpec(gpu=[{"vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768}], gpu_in_container=True, **CPU_OPTIONS)


def main():
    token = secrets.token_hex(24)
    server = make_server(FakeEngine(GPU_AND_CPU_SPEC), token)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        failures = run_checks(f"http://127.0.0.1:{server.server_address[1]}", token)
    finally:
        server.shutdown()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
