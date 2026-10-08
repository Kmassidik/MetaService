"""In-memory engine for the Fake Agent: pretends to be a machine with VMs and containers."""
import itertools
import threading
from dataclasses import dataclass, field

from contract.spec import CONTRACT_VERSION

DEFAULT_BUNDLE_VERSION = None
BACKUP_PREFIX = "backup"


@dataclass
class MachineSpec:
    os: str = "linux"
    arch: str = "x86_64"
    cpu_cores: int = 16
    ram_total_mb: int = 65536
    disk_total_gb: int = 2000
    reserve_ram_mb: int = 8192
    reserve_disk_gb: int = 100
    margin_disk_gb: int = 20
    gpu: list = field(default_factory=list)
    vm: bool = True
    container: bool = True
    gpu_in_vm: bool = False
    gpu_in_container: bool = False


class Refused(Exception):
    """A create the machine cannot take; carries the numbers behind the refusal."""

    def __init__(self, code, message, resource, needed, free):
        super().__init__(message)
        self.code, self.message = code, message
        self.resource, self.needed, self.free = resource, needed, free


class NotFound(Exception):
    pass


class FakeEngine:
    def __init__(self, spec=None, agent_version="fake-1"):
        self.spec = spec or MachineSpec()
        self.agent_version = agent_version
        self.bundle_version = DEFAULT_BUNDLE_VERSION
        self._workloads = {}
        self._commands = {}
        self._ids = itertools.count(1)
        self._lock = threading.Lock()

    # ---- read side -------------------------------------------------
    def facts(self):
        with self._lock:
            return self._facts()

    def _facts(self):
        spec = self.spec
        return {
            "os": spec.os, "arch": spec.arch, "cpu_cores": spec.cpu_cores,
            "ram_total_mb": spec.ram_total_mb, "disk_total_gb": spec.disk_total_gb,
            "free_ram_mb": self._free_ram(), "free_disk_gb": self._free_disk(),
            "gpu": list(spec.gpu),
            "capabilities": {
                "vm": spec.vm, "container": spec.container,
                "gpu_in_vm": spec.gpu_in_vm, "gpu_in_container": spec.gpu_in_container,
            },
        }

    def _free_ram(self):
        running = sum(w["ram_mb"] for w in self._workloads.values() if w["state"] == "running")
        return max(0, self.spec.ram_total_mb - self.spec.reserve_ram_mb - running)

    def _free_disk(self):
        used = sum(w["disk_gb"] for w in self._workloads.values())
        return max(0, self.spec.disk_total_gb - self.spec.reserve_disk_gb - self.spec.margin_disk_gb - used)

    def health(self):
        return {"status": "ok", "agent_version": self.agent_version,
                "contract_version": CONTRACT_VERSION, "bundle_version": self.bundle_version}

    def workloads(self):
        with self._lock:
            return [dict(w) for w in self._workloads.values()]

    def command(self, command_id):
        with self._lock:
            found = self._commands.get(command_id)
            if found is None:
                raise NotFound(command_id)
            return dict(found)

    # ---- write side ------------------------------------------------
    def create(self, body):
        with self._lock:
            existing = self._commands.get(body["command_id"])
            if existing is not None:
                return dict(existing)
            self._check_room(body)
            workload = self._new_workload(body)
            self._workloads[workload["id"]] = workload
            return self._finish(body["command_id"], "create", workload["id"], {"workload_id": workload["id"]})

    def _check_room(self, body):
        self._check_capability(body)
        if body["ram_mb"] > self._free_ram():
            raise Refused("not_enough_room", "not enough RAM", "ram_mb", body["ram_mb"], self._free_ram())
        if body["disk_gb"] > self._free_disk():
            raise Refused("not_enough_room", "not enough disk", "disk_gb", body["disk_gb"], self._free_disk())

    def _check_capability(self, body):
        kind, gpu_mode = body["kind"], body.get("gpu_mode", "none")
        allowed = {"vm": self.spec.vm, "container": self.spec.container}[kind]
        if not allowed:
            raise Refused("missing_capability", f"this machine cannot run a {kind}", "capability", 1, 0)
        gpu_ok = {"none": True, "container": self.spec.gpu_in_container, "passthrough": self.spec.gpu_in_vm}[gpu_mode]
        if not gpu_ok:
            raise Refused("missing_capability", f"gpu mode {gpu_mode} is not available here", "capability", 1, 0)

    def _new_workload(self, body):
        return {
            "id": f"wl-{next(self._ids)}", "name": body["name"], "kind": body["kind"], "state": "running",
            "cpu": body["cpu"], "ram_mb": body["ram_mb"], "disk_gb": body["disk_gb"],
            "gpu_mode": body.get("gpu_mode", "none"), "address": None, "bundle_version": None,
        }

    def set_state(self, command_id, workload_id, command_type, state):
        with self._lock:
            existing = self._commands.get(command_id)
            if existing is not None:
                return dict(existing)
            workload = self._get(workload_id)
            workload["state"] = state
            return self._finish(command_id, command_type, workload_id, {"state": state})

    def delete(self, command_id, workload_id):
        with self._lock:
            existing = self._commands.get(command_id)
            if existing is not None:
                return dict(existing)
            self._get(workload_id)
            del self._workloads[workload_id]
            backup = f"{BACKUP_PREFIX}-{workload_id}"
            return self._finish(command_id, "delete", workload_id, {"backup_id": backup})

    def install_bundle(self, body):
        with self._lock:
            existing = self._commands.get(body["command_id"])
            if existing is not None:
                return dict(existing)
            target = body.get("workload_id")
            if target is None:
                self.bundle_version = body["version"]
            else:
                self._get(target)["bundle_version"] = body["version"]
            return self._finish(body["command_id"], "bundle_install", target, {"version": body["version"]})

    def _get(self, workload_id):
        found = self._workloads.get(workload_id)
        if found is None:
            raise NotFound(workload_id)
        return found

    def _finish(self, command_id, command_type, workload_id, result):
        record = {"command_id": command_id, "type": command_type, "state": "succeeded", "result": result}
        if workload_id is not None:
            record["workload_id"] = workload_id
        self._commands[command_id] = record
        return dict(record)
