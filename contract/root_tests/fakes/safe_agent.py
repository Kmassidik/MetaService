"""The helper the Root black-box tests copy into their throwaway boxes: the real macOS helper behind a few lines of shell that answer `autostart` without doing it.

The real `autostart on` writes a LaunchAgent into the home of whoever runs it, and these tests run on the developer's own machine over SSH to itself: the real verb must never
run here. The lines answer it instead, and write down what was asked, so a check can assert that it was asked once, with the box, and after the helper was alive:

    <box>/state/autostart.calls   one line per call: the arguments, then `alive=yes|no` (was the helper from start.sh running at that moment)

The exit code it answers is 0, or what a file named by the test holds (3 means "one step left for the owner"). The file is outside the box, so a test can set it before the install.

Everything else goes to the real helper unchanged."""
import pathlib
import tempfile

from contract.agent_tests.support import MACOS_BINARY

CALLS_FILE = "autostart.calls"
NEEDS_OWNER = 3


def program_text(comment="the real helper", exit_file=None):
    # $0 is <box>/bin/metaservice-agent, the box being the folder above bin.
    answer = f'$(cat "{exit_file}" 2>/dev/null || echo 0)' if exit_file else "0"
    intercept = f"""if [ "$1" = autostart ]; then
  state="$(dirname "$0")/../state"
  if kill -0 "$(cat "$state/agent.pid" 2>/dev/null)" 2>/dev/null; then alive=yes; else alive=no; fi
  echo "$* alive=$alive" >> "$state/{CALLS_FILE}"
  exit {answer}
fi
"""
    return f'#!/bin/sh\n# {comment}\n{intercept}exec {MACOS_BINARY} "$@"\n'


_cached = []


def safe_agent():
    """One wrapper per test process, written where the Root can read it."""
    if not _cached:
        _cached.append(write_program(program_text()))
    return _cached[0]


def write_program(text):
    path = pathlib.Path(tempfile.mkdtemp(prefix="ms-safe-agent-")) / "metaservice-agent"
    path.write_text(text)
    path.chmod(0o755)
    return path


def calls(box):
    """The recorded `autostart` calls of a box, oldest first."""
    path = pathlib.Path(box) / "state" / CALLS_FILE
    return path.read_text().splitlines() if path.exists() else []
