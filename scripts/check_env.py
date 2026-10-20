#!/usr/bin/env python3
"""Checks the control plane's .env before anything is built or started, and says in plain words what to fix.

The rules are the same ones the parent enforces when it starts (control-plane/arm64/Sources/Root/Config/RootConfig.swift), checked here first so a typo
does not cost a build. It never prints a value, only the name of the setting. A missing file is fine: the parent makes the setup token itself.
Usage: check_env.py [path-to-.env]    Exit 0 when the file is fine, 1 when something must be fixed.
"""
import os
import re
import stat
import sys
from urllib.parse import urlparse

MIN_TOKEN_LENGTH = 16
PORTS = ("ROOT_PORT", "ROOT_AGENT_PORT", "AGENT_PORT")
AI_SETTINGS = ("AI_BASE_URL", "AI_API_KEY", "AI_DEFAULT_MODEL")
CLOUDFLARE_SETTINGS = ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_ZONE_ID")
CLOUDFLARE_ID = re.compile(r"^[0-9a-f]{32}$")


def read_env(text):
    """The same reading as the parent: comments skipped, quotes dropped, a blank value counts as not set."""
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip("\"'")
        if value:
            values[key.strip()] = value
    return values


def is_port(text):
    return text.isdigit() and 1 <= int(text) <= 65535


def problems_in(values, mode):
    """What is wrong, as sentences. `mode` is the file's permission bits, or None when it cannot be known."""
    found = []
    if mode is not None and mode & (stat.S_IRWXG | stat.S_IRWXO):
        found.append("The .env file can be read by other users. Fix: chmod 600 control-plane/arm64/.env")
    token = values.get("ROOT_SETUP_TOKEN")
    if token is not None and len(token) < MIN_TOKEN_LENGTH:
        found.append(f"ROOT_SETUP_TOKEN is too short ({len(token)} characters). It needs at least {MIN_TOKEN_LENGTH}. Make it longer, or empty the line and the parent makes one for you.")
    for name in PORTS:
        if name in values and not is_port(values[name]):
            found.append(f"{name} must be a whole number from 1 to 65535.")
    given = [name for name in AI_SETTINGS if name in values]
    if given and len(given) != len(AI_SETTINGS):
        missing = [name for name in AI_SETTINGS if name not in values]
        found.append(f"The AI settings are half filled: {', '.join(missing)} is missing. Set all three, or none of them.")
    return found + remote_access_problems(values)


def public_name(url):
    """The host of an https address with no port, path or login, or None when it is anything else."""
    parts = urlparse(url)
    plain = parts.scheme == "https" and parts.hostname and not parts.port and parts.path in ("", "/") and not parts.query and not parts.username
    return parts.hostname if plain else None


def remote_access_problems(values):
    """The settings for reaching the panel from outside: all three Cloudflare settings or none, real ids, an https name, and no borrowed tunnel."""
    found = []
    if "CLOUDFLARE_TUNNEL_ID" in values:
        found.append("CLOUDFLARE_TUNNEL_ID is not used here: MetaService makes a tunnel of its own, and another project's tunnel id must never be copied in. Remove that line.")
    given = [name for name in CLOUDFLARE_SETTINGS if name in values]
    if not given:
        return found
    missing = [name for name in CLOUDFLARE_SETTINGS if name not in values]
    if missing:
        return found + [f"The Cloudflare settings are half filled: {', '.join(missing)} is missing. Set all three, or none of them."]
    found += [f"{name} must be the 32-character id from the Cloudflare dashboard." for name in ("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_ZONE_ID") if not CLOUDFLARE_ID.match(values[name])]
    if not public_name(values.get("PUBLIC_BASE_URL", "")):
        found.append("PUBLIC_BASE_URL must be https://<name> with no port and no path (for example https://meta.example.com) when the Cloudflare settings are given.")
    return found


def check(path):
    if not os.path.exists(path):
        return []
    mode = stat.S_IMODE(os.stat(path).st_mode)
    with open(path, encoding="utf-8") as file:
        return problems_in(read_env(file.read()), mode)


def main(argv):
    path = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "control-plane", "arm64", ".env")
    found = check(path)
    if not found:
        return 0
    print(f"Fix these in {os.path.normpath(path)} before MetaService starts:", file=sys.stderr)
    for line in found:
        print(f"  - {line}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
