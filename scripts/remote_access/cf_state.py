"""What the tool made, kept in one owner-only file next to the control plane's other state, so removal undoes exactly that and nothing else.
It never holds the API token."""
from __future__ import annotations

import json
import os
import time

STATE_NAME = "remote-access.json"
BACKUP_FOLDER = "remote-access-backups"


def _private_write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    temporary = path + ".tmp"
    handle = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(handle, "w", encoding="utf-8") as file:
        file.write(text)
    os.replace(temporary, path)


def load(state_dir: str):
    path = os.path.join(state_dir, STATE_NAME)
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def save(state_dir: str, record: dict) -> None:
    _private_write(os.path.join(state_dir, STATE_NAME), json.dumps(record, indent=2, sort_keys=True) + "\n")


def forget(state_dir: str) -> None:
    path = os.path.join(state_dir, STATE_NAME)
    if os.path.exists(path):
        os.remove(path)


def backup_config(state_dir: str, config: dict) -> str:
    """The tunnel's whole route configuration as it was before a change, so a bad change can be put back."""
    name = time.strftime("ingress-%Y%m%d-%H%M%S.json", time.gmtime())
    path = os.path.join(state_dir, BACKUP_FOLDER, name)
    _private_write(path, json.dumps(config, indent=2, sort_keys=True) + "\n")
    return path
