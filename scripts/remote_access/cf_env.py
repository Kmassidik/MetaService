"""The settings the remote-access tool needs, read from the control plane's .env and checked before anything is called.
MetaService makes its OWN tunnel, so a CLOUDFLARE_TUNNEL_ID (that is another project's tunnel) is never read.

Nothing here prints a value. The token is kept out of every repr, so a stray print or traceback cannot leak it.
"""
from __future__ import annotations

import os
import re
import stat
from dataclasses import dataclass, field
from urllib.parse import urlparse

HOSTNAME = re.compile(r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
CLOUDFLARE_ID = re.compile(r"^[0-9a-f]{32}$")
REQUIRED = ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_ZONE_ID")
DEFAULT_TUNNEL_NAME = "metaservice"
TUNNEL_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$")
DEFAULT_PANEL_PORT = 9100


class SettingsError(Exception):
    """A problem in the settings, in a sentence that names the setting and never shows a value."""


@dataclass(frozen=True)
class Settings:
    token: str = field(repr=False)
    account_id: str = field(repr=False)
    zone_id: str = field(repr=False)
    host: str = ""
    origin: str = ""
    tunnel_name: str = DEFAULT_TUNNEL_NAME


def read_env(text: str) -> dict:
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


def load_env(path: str) -> dict:
    if not os.path.exists(path):
        raise SettingsError(f"{path} does not exist. Copy .env.example to .env and fill it in.")
    if stat.S_IMODE(os.stat(path).st_mode) & (stat.S_IRWXG | stat.S_IRWXO):
        raise SettingsError(f"{path} can be read by other users. Fix: chmod 600 {path}")
    with open(path, encoding="utf-8") as file:
        return read_env(file.read())


def host_from_public_url(url: str) -> str:
    parts = urlparse(url)
    if parts.scheme != "https" or not parts.hostname or parts.port or parts.path not in ("", "/") or parts.query or parts.username:
        raise SettingsError("PUBLIC_BASE_URL must be https://<hostname> with no port and no path, for example https://meta.example.com")
    return parts.hostname.lower()


def origin_from(values: dict) -> str:
    port = values.get("ROOT_PORT", str(DEFAULT_PANEL_PORT))
    if not (port.isdigit() and 1 <= int(port) <= 65535):
        raise SettingsError("ROOT_PORT must be a whole number from 1 to 65535.")
    return f"http://127.0.0.1:{port}"


def settings_from(values: dict, host: str = "", origin: str = "", tunnel_name: str = "") -> Settings:
    missing = [name for name in REQUIRED if name not in values]
    if missing:
        raise SettingsError("These settings are empty in the .env: " + ", ".join(missing))
    for name in ("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_ZONE_ID"):
        if not CLOUDFLARE_ID.match(values[name]):
            raise SettingsError(f"{name} must be the 32-character id from the Cloudflare dashboard.")
    wanted = host or (host_from_public_url(values["PUBLIC_BASE_URL"]) if "PUBLIC_BASE_URL" in values else "")
    if not wanted:
        raise SettingsError("PUBLIC_BASE_URL is empty: set it to https://<the hostname the panel should have>.")
    if not HOSTNAME.match(wanted):
        raise SettingsError("The hostname is not a valid name.")
    name = tunnel_name or DEFAULT_TUNNEL_NAME
    if not TUNNEL_NAME.match(name):
        raise SettingsError("The tunnel name may only have letters, digits, dots, dashes and underscores.")
    return Settings(values["CLOUDFLARE_API_TOKEN"], values["CLOUDFLARE_ACCOUNT_ID"], values["CLOUDFLARE_ZONE_ID"], wanted,
                    origin or origin_from(values), name)
