#!/usr/bin/env python3
"""Builds dist/metaservice-chat-<version>-noarch.tar.gz. The same sources always give the same bytes, so the checksum is stable.
Prints the sha256. Plain Python 3, so it runs the same on macOS and Linux."""
import gzip
import hashlib
import io
import json
import argparse
import pathlib
import sys
import tarfile

HERE = pathlib.Path(__file__).resolve().parent
FIXED_TIME = 946684800  # 2000-01-01, so file times never change the checksum
FILES = ["service/chat.py", "web/index.html", "web/chat.js", "web/chat.css", "VERSION"]


def manifest(version):
    return (json.dumps({"name": "metaservice-chat", "version": version, "platform": "noarch", "entry": "service/chat.py", "port": 9200}) + "\n").encode()


def add(archive, name, data, mode):
    info = tarfile.TarInfo(name)
    info.size, info.mtime, info.mode, info.uid, info.gid, info.uname, info.gname = len(data), FIXED_TIME, mode, 0, 0, "", ""
    archive.addfile(info, io.BytesIO(data))


def build(version=None, out_dir=None):
    version = version or (HERE / "VERSION").read_text().strip()
    entries = {name: (HERE / name).read_bytes() for name in FILES}
    entries["VERSION"] = (version + "\n").encode()
    entries["manifest.json"] = manifest(version)
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name in sorted(entries):
            add(archive, name, entries[name], 0o755 if name == "service/chat.py" else 0o644)
    out = pathlib.Path(out_dir or HERE / "dist") / f"metaservice-chat-{version}-noarch.tar.gz"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as target, gzip.GzipFile(fileobj=target, mode="wb", mtime=0, filename="", compresslevel=9) as zipped:
        zipped.write(raw.getvalue())
    return hashlib.sha256(out.read_bytes()).hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Build the chat bundle")
    parser.add_argument("--version", help="override the version in the VERSION file (used by tests)")
    parser.add_argument("--out", help="folder for the archive (default: dist/)")
    args = parser.parse_args()
    sys.stdout.write(build(args.version, args.out) + "\n")
