"""The Fake Agent's GET /v1/storage and POST /v1/storage/scan: a believable map of a 4 TB Linux machine's disk, with one hostile folder name.
Nothing is scanned: a scan "runs" for `scan_seconds` (progress climbing), then the same fixed map is served with the time it finished."""
import threading
import time
from datetime import datetime, timezone

GIB = 1024 ** 3
MIB = 1024 ** 2
HOSTILE_FOLDER = "<img src=x onerror=alert(3)>"
TOTAL_BYTES = 4031 * 10 ** 9
# The scan cannot open these (root only), so the first node is smaller than the used space by about this much.
HIDDEN_BYTES = 38 * GIB
NOW = 1_793_000_000
DAY = 86_400


def _file(name, bytes_, kind="other", reclaim=None, age_days=3):
    return {"name": name, "type": "file", "bytes": bytes_, "files": 1, "items": 0, "kind": kind, "reclaim": reclaim, "modified": NOW - age_days * DAY, "children": []}


def _rest(items, bytes_, files, kind="other", reclaim=None):
    return {"name": "", "type": "rest", "bytes": bytes_, "files": files, "items": items, "kind": kind, "reclaim": reclaim, "modified": NOW - 9 * DAY, "children": []}


def _dir(name, children, kind="other", reclaim=None, own=4096):
    """A folder: its numbers are its children's plus its own block, as the helper counts them."""
    return {"name": name, "type": "dir", "bytes": own + sum(c["bytes"] for c in children), "files": sum(c["files"] for c in children), "items": len(children),
            "kind": kind, "reclaim": reclaim, "modified": max((c["modified"] for c in children), default=NOW), "children": sorted(children, key=lambda c: -c["bytes"])}


def _tree():
    hf = _dir("huggingface", [_dir("hub", [_dir("models--Qwen--Qwen3-32B", [_file("model-00001-of-00004.safetensors", 18 * GIB, "cache", "regenerable"),
                                                                          _file("model-00002-of-00004.safetensors", 17 * GIB, "cache", "regenerable"),
                                                                          _rest(5, 9 * GIB, 5, "cache", "regenerable")], "cache", "regenerable"),
                                             _dir("models--black-forest-labs--FLUX.1-dev", [_rest(11, 23 * GIB, 11, "cache", "regenerable")], "cache", "regenerable")],
                                   "cache", "regenerable")], "cache", "regenerable")
    cache = _dir(".cache", [hf, _dir("pip", [_rest(820, 3 * GIB, 820, "cache", "regenerable")], "cache", "regenerable"), _rest(40, 900 * MIB, 610, "cache", "regenerable")],
                 "cache", "regenerable")
    models = _dir("models", [_file("deepseek-v4-q4.gguf", 61 * GIB, "media"), _file("llama-4-scout-q8.gguf", 34 * GIB, "media"), _rest(6, 4 * GIB, 6, "media")], "media")
    app = _dir("app", [_dir("target", [_dir("release", [_rest(1900, 7 * GIB, 1900, "code", "build_output")], "code", "build_output")], "code", "build_output"),
                       _dir(".git", [_rest(3, 600 * MIB, 140, "git")], "git"), _rest(80, 120 * MIB, 300, "code")], "code")
    web = _dir("web", [_dir("node_modules", [_rest(900, 2 * GIB, 41000, "cache", "reinstallable")], "cache", "reinstallable"), _rest(40, 300 * MIB, 500, "code")], "code")
    projects = _dir("projects", [app, web, _dir(HOSTILE_FOLDER, [_rest(3, 1 * GIB, 3, "code")], "code"), _rest(30, 900 * MIB, 4000, "code")], "code")
    user = _dir("ops", [cache, models, projects, _dir("Downloads", [_rest(14, 6 * GIB, 14, "documents")], "documents"), _rest(60, 2 * GIB, 9000, "other")])
    home = _dir("home", [user], "media")
    incus = _dir("incus", [_dir("disks", [_file("default.img", 120 * GIB, "vms")], "vms"), _dir("images", [_rest(4, 6 * GIB, 4, "vms")], "vms"), _rest(20, 300 * MIB, 200, "vms")], "vms")
    docker = _dir("docker", [_dir("overlay2", [_rest(300, 18 * GIB, 210000, "vms")], "vms"), _rest(10, 400 * MIB, 50, "vms")], "vms")
    lib = _dir("lib", [incus, docker, _dir("apt", [_rest(50, 300 * MIB, 90, "other")]), _rest(90, 2 * GIB, 30000, "other")])
    var = _dir("var", [lib, _dir("log", [_rest(200, 3 * GIB, 400, "other")]), _rest(20, 200 * MIB, 900, "other")])
    usr = _dir("usr", [_dir("lib", [_rest(2000, 9 * GIB, 60000, "other")]), _dir("local", [_dir("cuda-13.0", [_rest(40, 7 * GIB, 3000, "other")])]), _rest(10, 4 * GIB, 40000, "other")])
    tmp = _dir("tmp", [_rest(90, 5 * GIB, 300, "cache", "temporary")], "cache", "temporary")
    root = _dir("/", [home, var, usr, tmp, _file("swap.img", 16 * GIB, "other", age_days=40), _dir("opt", [_rest(30, 6 * GIB, 9000, "other")]), _rest(12, 1 * GIB, 5000, "other")])
    return root


def _flatten(root):
    nodes = []
    stack = [(root, -1)]
    while stack:
        entry, parent = stack.pop()
        place = len(nodes)
        nodes.append({key: entry[key] for key in ("name", "type", "bytes", "files", "items", "kind", "reclaim", "modified")} | {"parent": parent})
        for child in reversed(entry["children"]):
            stack.append((child, place))
    return nodes


class FakeStorage:
    """One fake machine's storage map. `scan_seconds` is how long a scan pretends to take."""

    def __init__(self, scan_seconds=1.5):
        self.scan_seconds = scan_seconds
        self.lock = threading.Lock()
        self.started = None
        self.finished = None
        self.scans = 0

    def _scanning(self, now):
        return self.started is not None and self.finished is None and now - self.started < self.scan_seconds

    def _settle(self, now):
        if self.started is not None and self.finished is None and now - self.started >= self.scan_seconds:
            self.finished = self.started + self.scan_seconds

    def answer(self):
        with self.lock:
            now = time.time()
            self._settle(now)
            scanning = self._scanning(now)
            share = min((now - self.started) / self.scan_seconds, 1.0) if scanning else 0
            nodes = _flatten(_tree())
            progress = {"entries": int(share * 1_400_000), "bytes": int(share * nodes[0]["bytes"])} if scanning else None
            return {"scanning": scanning, "progress": progress, "error": None, "map": self._map(nodes) if self.finished else None}

    def scan(self):
        with self.lock:
            now = time.time()
            self._settle(now)
            if not self._scanning(now):
                self.started, self.finished = now, None
                self.scans += 1
        return self.answer()

    def _map(self, nodes):
        used = nodes[0]["bytes"] + HIDDEN_BYTES
        return {"root": "/", "finished_at": datetime.fromtimestamp(self.finished, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "seconds": round(self.scan_seconds, 1),
                "entries": 1_400_000, "unreadable": 7, "disk": {"total_bytes": TOTAL_BYTES, "used_bytes": used, "free_bytes": TOTAL_BYTES - used}, "nodes": nodes}
