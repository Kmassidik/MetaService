"""The health watchdog: keeps the MetaService parent honest.

launchd's KeepAlive notices a process that *exits*; it cannot notice one that is still running but no longer answers. That is the
failure the panel shows as a dead page while `launchctl list` looks healthy. This asks the panel's /health every interval, and
after a few failures in a row stops and starts the parent through scripts/parent-service.sh.

  python3 scripts/watchdog.py [--root DIR] [--url URL] [--interval SECONDS] [--failures N] [--self-test]

It runs as the same person as the parent (a LaunchDaemon, `io.metaservice.watchdog`), writes to logs/watchdog.log, and keeps no
state: the counter lives in memory, so a watchdog restart starts counting again rather than restarting the parent at once.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://127.0.0.1:9100/health"
DEFAULT_INTERVAL = 20  # seconds between probes
DEFAULT_FAILURES = 3  # failures in a row before the parent is restarted
PROBE_TIMEOUT = 5  # a probe that takes longer than this is a failure
RESTART_TIMEOUT = 180  # the start script waits for the panel itself; give it room
RESET = "reset"
COUNT = "count"
RESTART = "restart"


def decide(healthy: bool, failures: int, threshold: int) -> str:
    """What to do after one probe: a healthy answer clears the count; the threshold-th failure in a row restarts the parent."""
    if healthy:
        return RESET
    return RESTART if failures + 1 >= threshold else COUNT


def probe(url: str, timeout: float = PROBE_TIMEOUT) -> bool:
    """True only when the panel answers 200. Any error, timeout or other status is a failure."""
    try:
        with urllib.request.urlopen(url, timeout=timeout) as answer:
            return answer.status == 200
    except (urllib.error.URLError, OSError, ValueError):
        return False


def restart(root: str) -> bool:
    """Stop then start the parent. True when the start script reports success."""
    for step in ("stop", "start"):
        done = subprocess.run(["sh", f"{root}/scripts/parent-service.sh", step], capture_output=True, text=True, timeout=RESTART_TIMEOUT)
        if step == "start":
            return done.returncode == 0
    return False


def say(text: str) -> None:
    print(time.strftime("%Y-%m-%dT%H:%M:%S%z"), text, flush=True)


def run(root: str, url: str, interval: int, threshold: int) -> int:
    failures = 0
    restarts = 0
    say(f"watchdog: watching {url} every {interval}s, restarting after {threshold} failures")
    while True:
        if probe(url):
            if failures:
                say(f"watchdog: the panel answers again after {failures} failed probe(s)")
            failures = 0
        else:
            failures += 1
            say(f"watchdog: no answer ({failures}/{threshold})")
            if decide(False, failures - 1, threshold) == RESTART:
                restarts += 1
                say(f"watchdog: restarting the parent (restart {restarts})")
                if restart(root):
                    say("watchdog: the parent restarted")
                else:
                    say("watchdog: the restart did not report success; the next failures will try again")
                failures = 0
        time.sleep(interval)


def self_test() -> int:
    """The rules, with no clock and no process: this is what `--self-test` checks in CI-style runs."""
    cases = [
        ((True, 0, 3), RESET),
        ((True, 2, 3), RESET),
        ((False, 0, 3), COUNT),
        ((False, 1, 3), COUNT),
        ((False, 2, 3), RESTART),
        ((False, 0, 1), RESTART),
    ]
    for (healthy, failures, threshold), wanted in cases:
        got = decide(healthy, failures, threshold)
        if got != wanted:
            print(f"FAIL decide(healthy={healthy}, failures={failures}, threshold={threshold}) = {got}, wanted {wanted}")
            return 1
    if probe("http://127.0.0.1:9/health", timeout=1):
        print("FAIL a closed port must not look healthy")
        return 1
    print(f"ok: {len(cases)} decide() cases and the closed-port probe")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Keep the MetaService parent answering.")
    parser.add_argument("--root", default=".", help="the repository folder (holds scripts/parent-service.sh)")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--interval", type=int, default=DEFAULT_INTERVAL)
    parser.add_argument("--failures", type=int, default=DEFAULT_FAILURES)
    parser.add_argument("--self-test", action="store_true", help="check the rules and exit")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.interval < 1 or args.failures < 1:
        parser.error("--interval and --failures must be at least 1")
    try:
        return run(args.root, args.url, args.interval, args.failures)
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
