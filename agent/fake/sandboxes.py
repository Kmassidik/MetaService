"""The Fake Agent's sandboxes: the records, end times and events a real helper keeps, in memory (contract/openapi.yaml and sandbox/README.md).

The same shape a real helper answers, with none of the work: `sandbox` records are plain dicts, the end-time sweep runs on every request instead of on a
timer, and the way into a sandbox answers 501, because a pretended sandbox has no network and nothing inside it.
"""
import calendar
import hashlib
import json
import time
from collections import deque

BASE_TEMPLATE = "base"
BASE_BUILD = "1"
BASE_SIZE_MB = 1024
# When the stock template was built: a moment like any other, so the list has a time to show.
BASE_BUILT_AT = 1_792_800_000
# How many sandboxes may run on one pretended machine, and what one of them may take: the same rules a real helper keeps.
MAX_RUNNING = 32
# A sandbox may take this share of what the machine is allowed to hand out, as on a real helper.
SHARE_OF_MACHINE = 4
MB_PER_GB = 1024
EVENTS_KEPT = 10_000
EVENT_SECONDS = 86_400
GONE_IDS = 1_000
DEFAULT_LIMIT = 500
MAX_LIMIT = 1_000
# The smallest sandbox a machine still takes, as on a real helper.
MIN_RAM_MB = 256
MIN_DISK_MB = 512
TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
NO_PORT_PROXY = "this helper cannot pass a request into a sandbox yet: it has no network for one"


def iso(seconds):
    """A moment as the contract writes it."""
    return time.strftime(TIME_FORMAT, time.gmtime(seconds))


def parse_time(text):
    """The seconds of a contract time, or None when the text is not exactly one."""
    try:
        moment = time.strptime(text, TIME_FORMAT)
    except (TypeError, ValueError):
        return None
    return calendar.timegm(moment)


def elapsed_ms(found, now):
    """How long a sandbox had been running at that moment, in milliseconds."""
    return int((now - found["started"]) * 1000)


def fingerprint(body):
    """A stable name for a create body, so a retry with the same id and the same body is answered with the same sandbox."""
    return hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()


class SandboxRefused(Exception):
    """The machine cannot take this sandbox; carries the numbers behind the refusal."""

    def __init__(self, code, message, resource=None, needed=None, free=None):
        super().__init__(message)
        self.code, self.message = code, message
        self.resource, self.needed, self.free = resource, needed, free

    def error(self):
        plain = {"code": self.code, "message": self.message}
        if self.resource is None:
            return plain
        return {**plain, "resource": self.resource, "needed": self.needed, "free": self.free}


class SandboxTooOld(Exception):
    """The events asked for are no longer kept."""


class SandboxNotFound(Exception):
    """This helper never had that sandbox, or it is gone."""


class FakeSandboxes:
    def __init__(self, spec):
        self.spec = spec
        self._sandboxes = {}
        self._gone = deque()
        self._was_known = set()
        self._events = []
        self._seq = 0

    # ---- read side -------------------------------------------------
    def limits(self):
        spec = self.spec
        return {"max_running": MAX_RUNNING, "max_vcpu": max(spec.cpu_cores, 1),
                "max_ram_mb": max(spec.ram_total_mb // SHARE_OF_MACHINE, MIN_RAM_MB), "max_disk_mb": max(spec.disk_total_gb * MB_PER_GB // SHARE_OF_MACHINE, MIN_DISK_MB)}

    def list(self):
        self._sweep()
        return [self._view(found) for found in self._sandboxes.values()]

    def get(self, sandbox_id):
        self._sweep()
        return self._view(self._found(sandbox_id))

    def metrics(self, sandbox_id):
        found = self._found(sandbox_id)
        return [{"at": iso(time.time()), "cpu_count": found["vcpu"], "cpu_used_pct": 0.0, "mem_used_mb": 0, "mem_total_mb": found["ram_mb"],
                 "disk_used_mb": 0, "disk_total_mb": found["disk_mb"]}]

    def templates(self):
        return [{"id": BASE_TEMPLATE, "build": BASE_BUILD, "state": "ready", "built_at": iso(BASE_BUILT_AT), "size_mb": BASE_SIZE_MB, "message": None}]

    def events(self, after, limit=DEFAULT_LIMIT):
        oldest = max(self._seq - len(self._events), 0)
        if after < oldest:
            raise SandboxTooOld()
        return {"events": [dict(event, at=iso(event["at"])) for event in self._events if event["seq"] > after][:limit], "last": self._seq}

    def facts(self):
        """What this helper offers for sandboxes, for `Facts.sandbox`: worked out now, so the numbers match what a create would find."""
        self._sweep()
        limits = self.limits()
        booked = {"vcpu": sum(f["vcpu"] for f in self._sandboxes.values()), "ram_mb": sum(f["ram_mb"] for f in self._sandboxes.values()),
                  "disk_mb": sum(f["disk_mb"] for f in self._sandboxes.values())}
        return {"engine": {"name": "simulated", "version": None}, "max_running": limits["max_running"], "running": len(self._sandboxes), "paused": 0,
                "max_vcpu": limits["max_vcpu"], "max_ram_mb": limits["max_ram_mb"], "max_disk_mb": limits["max_disk_mb"], "booked": booked,
                "templates": [{"id": BASE_TEMPLATE, "build": BASE_BUILD, "ready": True}], "changes": self._seq}

    # ---- write side ------------------------------------------------
    def create(self, body):
        """Makes a sandbox and answers (status, record): 201 for a new one, 200 for the same id and body sent again."""
        self._sweep()
        fingerprint_of_body = fingerprint(body)
        existing = self._sandboxes.get(body["id"])
        if existing is not None:
            if existing["fingerprint"] != fingerprint_of_body:
                raise SandboxRefused("id_taken", "this id was used before, for another sandbox")
            return 200, self._view(existing)
        # An id this helper had and no longer has cannot be answered with that sandbox again, so it is not given to a new one either.
        if body["id"] in self._was_known:
            raise SandboxRefused("id_taken", "this id was used before, for another sandbox")
        self._check_template(body["template"])
        self._check_room(body)
        found = {"id": body["id"], "template": body["template"], "build": BASE_BUILD, "vcpu": body["vcpu"], "ram_mb": body["ram_mb"], "disk_mb": body["disk_mb"],
                 "internet": body["internet"], "started": time.time(), "end": parse_time(body["end_at"]), "on_end": body["on_end"],
                 "fingerprint": fingerprint_of_body, "running_ms": 0}
        self._sandboxes[found["id"]] = found
        self._record(found["id"], "started", None, time.time(), 0)
        return 201, self._view(found)

    def set_end(self, sandbox_id, body):
        found = self._found(sandbox_id)
        found["end"] = parse_time(body["end_at"])
        found["on_end"] = body["on_end"]
        return self._view(found)

    def delete(self, sandbox_id):
        """Removes it. A sandbox this helper had and no longer has is not an error; one it never had is a 404 (NotFound from `_found`)."""
        self._sweep()
        found = self._sandboxes.pop(sandbox_id, None)
        if found is None:
            if sandbox_id not in self._was_known:
                raise SandboxNotFound(sandbox_id)
            return
        now = time.time()
        self._forget(sandbox_id)
        self._record(sandbox_id, "ended", "deleted", now, elapsed_ms(found, now))

    # ---- the end times and the events ------------------------------
    def _sweep(self):
        """Ends every sandbox whose time has come. A real helper does this on a timer; this one does it whenever it is asked something."""
        now = time.time()
        for sandbox_id in [found["id"] for found in self._sandboxes.values() if found["end"] <= now]:
            found = self._sandboxes.pop(sandbox_id)
            self._forget(sandbox_id)
            self._record(sandbox_id, "ended", "timeout", now, elapsed_ms(found, now))

    def _forget(self, sandbox_id):
        if sandbox_id in self._was_known:
            return
        self._was_known.add(sandbox_id)
        self._gone.append(sandbox_id)
        while len(self._gone) > GONE_IDS:
            self._was_known.discard(self._gone.popleft())

    def _record(self, sandbox_id, kind, reason, now, running_ms):
        self._seq += 1
        event = {"seq": self._seq, "at": now, "id": sandbox_id, "kind": kind, "running_ms": running_ms}
        if reason is not None:
            event["reason"] = reason
        self._events.append(event)
        while len(self._events) > EVENTS_KEPT or now - self._events[0]["at"] > EVENT_SECONDS:
            self._events.pop(0)

    def _check_template(self, template):
        """Only the stock template is built on a pretended machine, as on a real one until templates are built from the panel."""
        if template != BASE_TEMPLATE:
            raise SandboxRefused("template_not_ready", f"this machine has no ready template called {template}")

    def _check_room(self, body):
        limits = self.limits()
        booked = {"vcpu": sum(f["vcpu"] for f in self._sandboxes.values()), "ram_mb": sum(f["ram_mb"] for f in self._sandboxes.values()),
                  "disk_mb": sum(f["disk_mb"] for f in self._sandboxes.values())}
        free = [("slots", 1, limits["max_running"] - len(self._sandboxes), "this machine is running all the sandboxes it may run"),
                ("vcpu", body["vcpu"], limits["max_vcpu"] - booked["vcpu"], "not enough vCPU left on this machine for this sandbox"),
                ("ram_mb", body["ram_mb"], limits["max_ram_mb"] - booked["ram_mb"], "not enough memory left on this machine for this sandbox"),
                ("disk_mb", body["disk_mb"], limits["max_disk_mb"] - booked["disk_mb"], "not enough disk left on this machine for this sandbox")]
        for resource, needed, room, message in free:
            if needed > room:
                raise SandboxRefused("not_enough_room", message, resource, needed, max(room, 0))

    def _found(self, sandbox_id):
        found = self._sandboxes.get(sandbox_id)
        if found is None:
            raise SandboxNotFound(sandbox_id)
        return found

    def _view(self, found):
        now = time.time()
        return {"id": found["id"], "template": found["template"], "build": found["build"], "state": "running", "vcpu": found["vcpu"], "ram_mb": found["ram_mb"],
                "disk_mb": found["disk_mb"], "internet": found["internet"], "started_at": iso(found["started"]), "end_at": iso(found["end"]),
                "on_end": found["on_end"], "running_ms": elapsed_ms(found, now), "daemon_version": None}
