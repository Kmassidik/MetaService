"""The tunnel's connector: a launchd job of its own, so MAAS's cloudflared service is never touched. It runs `cloudflared tunnel run
--token-file`, so the token is in an owner-only file and never on a command line."""
from __future__ import annotations

import os
import shutil
import subprocess
from xml.sax.saxutils import escape

LABEL = "io.metaservice.cloudflared"
DAEMON_LABEL = "io.metaservice.connector"  # the same connector as a boot-time system daemon (./install.sh autostart on)
DAEMONS_DIR_VARIABLE = "METASERVICE_DAEMONS_DIR"
DEFAULT_DAEMONS_DIR = "/Library/LaunchDaemons"
BINARY_PLACES = ("/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared")


class ConnectorError(Exception):
    pass


def find_binary(which=shutil.which, exists=os.path.exists) -> str:
    found = which("cloudflared") or next((path for path in BINARY_PLACES if exists(path)), "")
    if not found:
        raise ConnectorError("cloudflared is not installed on this Mac. Install it first (Homebrew: brew install cloudflared).")
    return found


# TCP (http2) rather than the default QUIC: an office router that drops UDP stalls QUIC for minutes, TCP reconnects at once.
TRANSPORT = ("--protocol", "http2")


def program_arguments(binary: str, token_file: str) -> tuple:
    """The connector's command line. scripts/autostart_plists.py uses it too, so the boot-time daemon runs exactly what the user job runs."""
    return (binary, "tunnel", "--no-autoupdate", *TRANSPORT, "run", "--token-file", token_file)


def plist_text(binary: str, token_file: str, log_file: str) -> str:
    arguments = "".join(f"<string>{escape(part)}</string>" for part in program_arguments(binary, token_file))
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            f'<plist version="1.0"><dict><key>Label</key><string>{LABEL}</string>'
            f"<key>ProgramArguments</key><array>{arguments}</array>"
            "<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>"
            "<key>LimitLoadToSessionType</key><array><string>Aqua</string><string>Background</string></array>"
            f"<key>StandardOutPath</key><string>{escape(log_file)}</string><key>StandardErrorPath</key><string>{escape(log_file)}</string>"
            "</dict></plist>\n")


def daemon_installed(environ=os.environ) -> bool:
    """True when ./install.sh autostart on has installed the connector as a system daemon. Then that daemon is the connector, and no user job is made."""
    folder = environ.get(DAEMONS_DIR_VARIABLE, DEFAULT_DAEMONS_DIR)
    return os.path.exists(os.path.join(folder, DAEMON_LABEL + ".plist"))


class Launchd:
    """launchctl for this user. A Mac with someone at the screen has the gui domain; a headless one has only the user domain."""

    def __init__(self, uid: int, run=subprocess.run, program: str = "launchctl"):
        self._uid = uid
        self._run = run
        self._program = program

    def _launchctl(self, *arguments: str) -> bool:
        return self._run([self._program, *arguments], capture_output=True, text=True, timeout=30).returncode == 0

    def domains(self) -> list:
        return [f"gui/{self._uid}", f"user/{self._uid}"]

    def start(self, plist_path: str) -> str:
        for domain in self.domains():
            self._launchctl("bootout", f"{domain}/{LABEL}")
            if self._launchctl("bootstrap", domain, plist_path):
                return domain
        raise ConnectorError("launchd would not load the connector job.")

    def stop(self) -> None:
        for domain in self.domains():
            self._launchctl("bootout", f"{domain}/{LABEL}")

    def is_loaded(self) -> bool:
        user_job = any(self._launchctl("print", f"{domain}/{LABEL}") for domain in self.domains())
        return user_job or self._launchctl("print", f"system/{DAEMON_LABEL}")
