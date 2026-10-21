"""Writes the two boot-time LaunchDaemon plists for ./install.sh autostart on. Pure file writing: no launchctl, no sudo.

  python3 scripts/autostart_plists.py --root DIR --out DIR --user NAME --home DIR

It prints one line per plist: `wrote <path>` or `skipped <label>: <reason>`. The parent plist is always written; the connector plist only
when state/cloudflared.token exists and a cloudflared binary is found. The connector's command line comes from remote_access/cf_connector.py.
"""
from __future__ import annotations

import argparse
import os
import plistlib
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "remote_access"))

import cf_connector  # noqa: E402

PARENT_LABEL = "io.metaservice.parent"
CONNECTOR_LABEL = cf_connector.DAEMON_LABEL
CONTROL_PLANE = os.path.join("control-plane", "arm64")
PARENT_BINARY = os.path.join(CONTROL_PLANE, ".build", "debug", "metaservice-root")
TOKEN_FILE = "cloudflared.token"
CONNECTOR_LOG = "cloudflared.log"
PARENT_LOG = "parent.log"
GROUP = "staff"
RESTART_SECONDS = 10
DAEMON_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
CLOUDFLARED_VARIABLE = "METASERVICE_CLOUDFLARED"  # for tests: the path to use instead of searching for cloudflared


def base_job(label: str, arguments: list, user: str, home: str, log_file: str) -> dict:
    return {"Label": label, "ProgramArguments": arguments, "UserName": user, "GroupName": GROUP, "RunAtLoad": True, "KeepAlive": True,
            "ThrottleInterval": RESTART_SECONDS, "StandardOutPath": log_file, "StandardErrorPath": log_file,
            "EnvironmentVariables": {"PATH": DAEMON_PATH, "HOME": home}}


def parent_job(root: str, user: str, home: str) -> dict:
    working_folder = os.path.join(root, CONTROL_PLANE)  # the parent finds its .env and state/ from here
    job = base_job(PARENT_LABEL, [os.path.join(root, PARENT_BINARY)], user, home, os.path.join(working_folder, "run", PARENT_LOG))
    job["WorkingDirectory"] = working_folder
    return job


def find_cloudflared() -> str:
    override = os.environ.get(CLOUDFLARED_VARIABLE)
    if override is None:
        return cf_connector.find_binary()
    if not os.path.exists(override):
        raise cf_connector.ConnectorError(f"cloudflared was not found at {override}.")
    return override


def connector_job(root: str, user: str, home: str) -> dict:
    state_dir = os.path.join(root, CONTROL_PLANE, "state")
    token_file = os.path.join(state_dir, TOKEN_FILE)
    if not os.path.exists(token_file):
        raise cf_connector.ConnectorError(f"there is no {token_file} (run ./install.sh remote up first).")
    arguments = list(cf_connector.program_arguments(find_cloudflared(), token_file))
    return base_job(CONNECTOR_LABEL, arguments, user, home, os.path.join(state_dir, CONNECTOR_LOG))


def write_plist(out_dir: str, job: dict) -> str:
    path = os.path.join(out_dir, job["Label"] + ".plist")
    with open(path, "wb") as file:
        plistlib.dump(job, file)
    return path


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(prog="autostart_plists")
    for name in ("root", "out", "user", "home"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args(argv)
    print("wrote " + write_plist(args.out, parent_job(args.root, args.user, args.home)))
    try:
        job = connector_job(args.root, args.user, args.home)
    except cf_connector.ConnectorError as reason:
        print(f"skipped {CONNECTOR_LABEL}: {reason}")
        return 0
    print("wrote " + write_plist(args.out, job))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
