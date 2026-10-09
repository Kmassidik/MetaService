"""Run every conformance check against the Rust (Linux) Agent. See run_macos_agent for how it works. Use --incus for the Incus engine on a fake program."""
import pathlib

from contract.tests.run_macos_agent import main

BINARY = pathlib.Path(__file__).resolve().parents[2] / "agent" / "linux" / "target" / "debug" / "metaservice-agent"

if __name__ == "__main__":
    main(BINARY)
