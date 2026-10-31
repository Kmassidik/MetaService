"""The Fake Agent's GET /v1/security/events: a small deterministic log of a helper (failed logins, logins, a block, an unblock, hostile text) and a baseline with a warning.
It honours `after` and `limit`, can pretend its log was rotated (the cursor is then unknown and the answer says `reset`), and can fail or hang on purpose."""
import re
import threading
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit

DEFAULT_LIMIT = 500
MIN_LIMIT, MAX_LIMIT = 1, 2000
HANG_SECONDS = 15
MODE_OK, MODE_ERROR, MODE_HANG = "ok", "error", "hang"
MODES = (MODE_OK, MODE_ERROR, MODE_HANG)
CURSOR = re.compile(r"^g(\d+)-(\d+)$")
HOSTILE_USER = "<script>x</script>"
HOSTILE_ADDRESS_TEXT = "not an address!"
BASELINE = {"password_login": True, "ban_tool": "running", "firewall": False, "auto_updates": True, "starts_after_reboot": True, "pending_updates": 7}
BLOCK_ENDS_IN = timedelta(hours=1)

# What the log below adds up to once the parent has cleaned it (the black-box checks compare with these).
FAILED_TOTAL = 17
FAILED_BY_USER = {"root": 11, "admin": 3, HOSTILE_USER: 2, "bad user": 1}
FAILED_BY_ADDRESS = {"45.13.2.9": 10, "91.200.1.7": 6}
BLOCKED_NOW_ADDRESS = "45.13.2.9"
EVENTS_IN_LOG = 11


def iso(moment):
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def failed(ago, user, address, count):
    return {"ago": ago, "type": "failed_login", "user": user, "address": address, "method": None, "count": count, "until": None, "detail": None}


def single(ago, kind, user, address, method=None, until_in=None, detail=None):
    return {"ago": ago, "type": kind, "user": user, "address": address, "method": method, "count": 1, "until": until_in, "detail": detail}


def standard_log():
    hour = timedelta(hours=1)
    minute = timedelta(minutes=1)
    return [
        failed(3 * hour, "root", "45.13.2.9", 5),
        failed(3 * hour, "admin", "45.13.2.9", 3),
        failed(2 * hour, "root", "91.200.1.7", 4),
        failed(2 * hour, HOSTILE_USER, "91.200.1.7", 2),
        failed(110 * minute, "bad\nuser\x07", HOSTILE_ADDRESS_TEXT, 1),
        single(105 * minute, "login", "kurnia", "10.0.0.5", method="key"),
        single(100 * minute, "login", "kurnia", "10.0.0.6", method="password"),
        single(hour, "blocked", None, "45.13.2.9", until_in=BLOCK_ENDS_IN, detail="fail2ban sshd"),
        single(55 * minute, "blocked", None, "91.200.1.7", until_in=BLOCK_ENDS_IN),
        single(30 * minute, "unblocked", None, "91.200.1.7"),
        failed(20 * minute, "root", "45.13.2.9", 2),
    ]


class FakeSecurity:
    """One fake helper's security log. `mode` ok, error (a 500) or hang (no answer for a long time)."""

    def __init__(self, log=None):
        self.started = datetime.now(timezone.utc)
        self.events = list(log if log is not None else standard_log())
        self.generation = 1
        self.mode = MODE_OK
        self.baseline = dict(BASELINE)
        self.calls = []
        self._lock = threading.Lock()

    def set_mode(self, mode):
        self.mode = mode

    def rotate(self):
        """The log was rotated: every cursor handed out so far is unknown from now on."""
        with self._lock:
            self.generation += 1

    def append(self, event):
        """A new event, as {"ago_seconds", "type", "user", "address", "method", "count"}."""
        with self._lock:
            self.events.append({"ago": timedelta(seconds=event.get("ago_seconds", 0)), "type": event["type"], "user": event.get("user"), "address": event.get("address"),
                                "method": event.get("method"), "count": event.get("count", 1), "until": None, "detail": event.get("detail")})

    def answer(self, path):
        """(status, body) for GET /v1/security/events?after=&limit=."""
        query = parse_qs(urlsplit(path).query, keep_blank_values=True)
        with self._lock:
            self.calls.append(path)
        if self.mode == MODE_HANG:
            time.sleep(HANG_SECONDS)
        if self.mode != MODE_OK:
            return 500, {"error": {"code": "internal", "message": "internal error"}}
        limit = self._limit(query)
        if limit is None:
            return 400, {"error": {"code": "invalid_input", "message": f"limit must be a whole number from {MIN_LIMIT} to {MAX_LIMIT}"}}
        return 200, self._page(query.get("after", [None])[0], limit)

    @staticmethod
    def _limit(query):
        values = query.get("limit")
        if values is None:
            return DEFAULT_LIMIT
        text = values[0]
        return int(text) if len(values) == 1 and text.isdigit() and MIN_LIMIT <= int(text) <= MAX_LIMIT else None

    def _page(self, after, limit):
        with self._lock:
            start, reset = self._start(after)
            chosen = self.events[start:start + limit]
            return {
                "cursor": f"g{self.generation}-{start + len(chosen)}", "reset": reset,
                "events": [self._wire(event) for event in chosen], "baseline": dict(self.baseline),
            }

    def _start(self, after):
        """Where to read from, and whether the cursor could not be honoured. No cursor is a first read, not a reset."""
        if not after:
            return 0, False
        match = CURSOR.match(after)
        if match is None or int(match.group(1)) != self.generation or int(match.group(2)) > len(self.events):
            return 0, True
        return int(match.group(2)), False

    def _wire(self, event):
        until = event["until"]
        return {
            "time": iso(self.started - event["ago"]), "type": event["type"], "user": event["user"], "address": event["address"], "method": event["method"],
            "count": event["count"], "until": iso(datetime.now(timezone.utc) + until) if until is not None else None, "detail": event["detail"],
        }
