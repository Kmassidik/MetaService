"""The Fake Agent's GET /v1/stats: believable numbers that change on every call, and hostile process names.
The processes carry a command line holding a secret; it is never sent, which is what the black-box checks look for."""
import itertools
import math
import threading
import time
from datetime import datetime, timezone

from agent.fake import stats_gpu
from agent.fake.stats_extras import EXTRAS_FULL, Extras

GIB = 1024 ** 3
SECRET_COMMAND_LINE = "node server.js --api-key SECRET-FAKE-COMMAND-LINE-VALUE-0451"
HOSTILE_NAME = "<img src=x onerror=alert(1)>"
HOSTILE_USER = "<script>alert(2)</script>"
MAX_PROCESSES = 15
NAME_LIMIT = 64
PROCESS_COUNT_SENT = 20
HOSTILE_CPU_FLOOR = 60.0
FIRST_PID = 300
PROCESSES_PARAMETER = "processes"


def wants_processes(query):
    """The optional ?processes= of GET /v1/stats: absent or `1` keeps the program list, `0` leaves it out, anything else is None (refused)."""
    pairs = [pair.partition("=") for pair in query.split("&") if pair]
    values = [value for key, _, value in pairs if key == PROCESSES_PARAMETER]
    if not values:
        return True
    if len(values) != 1 or values[0] not in ("0", "1"):
        return None
    return values[0] == "1"


class FakeStats:
    """One fake machine's readings. `cores` many logical CPUs (threads) on `physical` cores (default: as many, no hyper-threading), `gpu` adds one NVIDIA card (`gpus` is a list of kinds from agent.fake.stats_gpu, one card each, for machines with several GPUs of different makers),
    `hostile` puts markup in names, `extras` says which optional numbers it sends: "full" (a Linux machine), "mac" or "none" (an older helper)."""

    def __init__(self, cores=8, gpu=False, hostile=True, measuring_first=True, physical=None, extras=EXTRAS_FULL, gpus=()):
        self.cores, self.hostile, self.measuring_first = cores, hostile, measuring_first
        self.gpus = tuple(gpus) or ((stats_gpu.KIND_NVIDIA,) if gpu else ())
        self.extras = Extras(extras, cores, physical or cores)
        self.calls = 0
        self.queries = []  # the raw query text of every request, so a check can see what the parent passed on
        self.calls_with_processes = 0
        self.calls_without_processes = 0
        self._lock = threading.Lock()
        self._ticks = itertools.count(1)

    def reading(self, with_processes=True):
        """with_processes False: the list is empty, as a helper that skipped the scan answers."""
        with self._lock:
            self.calls += 1
            if with_processes:
                self.calls_with_processes += 1
            else:
                self.calls_without_processes += 1
            tick = next(self._ticks)
        measuring = self.measuring_first and tick == 1
        reading = {
            "taken_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "measuring": measuring,
            "uptime_seconds": 86400 + tick,
            "cpu": self._cpu(tick, measuring),
            "memory": self._memory(tick),
            "disks": self._disks(),
            "network": self._network(tick, measuring),
            "processes": self._processes(tick, measuring) if with_processes else [],
            **self.extras.top(tick, measuring),
        }
        gpus = stats_gpu.readings(self.gpus, tick)
        if gpus:
            reading["gpus"] = gpus
        return reading

    def _wave(self, tick, core=0, low=5.0, high=95.0):
        return round(low + (high - low) * (0.5 + 0.5 * math.sin(tick * 0.9 + core)), 1)

    def _cpu(self, tick, measuring):
        cores = None if measuring else [self._wave(tick, core) for core in range(self.cores)]
        total = None if measuring else round(sum(cores) / len(cores), 1)
        load = {"one": round(1.5 + math.sin(tick) * 0.4, 2), "five": 1.1, "fifteen": 0.8}
        return {"core_count": self.cores, "total_percent": total, "cores_percent": cores, "load": load, **self.extras.cpu(tick, measuring, total)}

    def _memory(self, tick):
        total = 36 * GIB
        used = int((12 + tick % 7) * GIB)
        cached = 9 * GIB
        return {"total_bytes": total, "used_bytes": used, "cached_bytes": cached, "free_bytes": total - used - cached, "swap_total_bytes": 0, "swap_used_bytes": 0}

    def _disks(self):
        return [{"mount": "/", "name": "Macintosh HD", "fs": "apfs", "total_bytes": 494 * GIB, "used_bytes": 200 * GIB, "free_bytes": 294 * GIB},
                {"mount": "/Volumes/Data", "name": "Data", "fs": "apfs", "total_bytes": 2000 * GIB, "used_bytes": 1500 * GIB, "free_bytes": 500 * GIB}]

    def _network(self, tick, measuring):
        rate = None if measuring else float(120_000 + tick * 10_000)
        return {"received_total_bytes": tick * 1_000_000, "sent_total_bytes": tick * 400_000, "received_bytes_per_second": rate, "sent_bytes_per_second": None if measuring else rate / 4, **self.extras.network(tick)}

    def _processes(self, tick, measuring):
        everything = [self._process(tick, index, measuring) for index in range(PROCESS_COUNT_SENT)]
        everything.sort(key=lambda p: (-(p["cpu_percent"] or 0), -p["memory_bytes"], p["pid"]))
        return everything[:MAX_PROCESSES]

    def _process(self, tick, index, measuring):
        name = HOSTILE_NAME if self.hostile and index == 0 else f"worker-{index}"
        user = HOSTILE_USER if self.hostile and index == 1 else "kurnia"
        cpu = None if measuring else self._wave(tick, index, HOSTILE_CPU_FLOOR if self.hostile and index == 0 else 0.0, 99.0 - index)  # the hostile program stays among the busiest 15
        # `cmdline` exists only here, on the fake machine; the answer is built from the fields below and never contains it.
        process = {"pid": FIRST_PID + index, "name": name, "user": user, "cpu_percent": cpu, "memory_bytes": (200 - index * 5) * 1024 * 1024, "cmdline": SECRET_COMMAND_LINE}
        shown = {key: process[key] for key in ("pid", "name", "user", "cpu_percent", "memory_bytes")}
        return {**shown, **self.extras.threads(index)}
