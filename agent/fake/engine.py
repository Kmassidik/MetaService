"""In-memory engine for the Fake Agent: pretends to be a machine with VMs and containers."""
import copy
import hashlib
import itertools
import threading
import time
from dataclasses import dataclass, field

from agent.fake.apps import APP_IMAGES, FakeApps
from agent.fake.sandboxes import FakeSandboxes
from contract.spec import CONTRACT_VERSION

DEFAULT_BUNDLE_VERSION = None
# The build the Fake Agent reports unless told another: the SHA-256 of the text "fake-agent".
DEFAULT_AGENT_BUILD = hashlib.sha256(b"fake-agent").hexdigest()
BACKUP_PREFIX = "backup"
ENGINE_NAME = "fake"
ENGINE_VERSION = "1.0.0"
KEPT_CHAT_DATA = "chat-data"
NO_TOOLKIT_MESSAGE = "This machine has an NVIDIA GPU but not the NVIDIA container toolkit, so containers cannot use it yet. Install the toolkit on the machine first."
NO_GPU_MESSAGE = "This machine has no NVIDIA GPU to share with a container."
# What the GPU check finds inside a container, by the name a test picks in MachineSpec.gpu_inside.
GPU_INSIDE = {
    "nvidia-smi": {"gpu_visible": True, "how": "nvidia-smi", "detail": "NVIDIA GeForce RTX 5090, 580.178.04, 32607 MiB", "note": "The GPU is visible inside, and nvidia-smi can talk to it."},
    "device nodes": {"gpu_visible": True, "how": "device nodes", "detail": "/dev/nvidia0, /dev/nvidiactl. NVRM version: NVIDIA UNIX x86_64 Kernel Module  580.178.04", "note": "The GPU device is there but nvidia-smi is not installed in this image."},
    "none": {"gpu_visible": False, "how": "none", "detail": "", "note": "The GPU is not visible inside: there is no nvidia-smi and no NVIDIA device file."},
    "hostile": {"gpu_visible": True, "how": "nvidia-smi", "detail": "<img src=x onerror=alert(1)> <script>window.pwned=1</script>", "note": "The GPU is visible inside, and nvidia-smi can talk to it."},
}
NOT_GIVEN = {"gpu_visible": False, "how": "none", "detail": "", "note": "No GPU was given to this one."}
# What the machine has prepared: the stock image is always there.
BLANK_IMAGE = {"id": "blank", "ready": True, "built_at": None}
# The CPU models a VM can be given, as in Proxmox's Processors window: host first, the machine's own CPU, which every VM got before.
HOST_CPU_MODEL = "host"
CPU_MODELS = (HOST_CPU_MODEL, "EPYC", "EPYC-Rome", "EPYC-Milan", "EPYC-Genoa", "Skylake-Server", "Icelake-Server")
# The CPU flags a VM can have switched on or off. nested-virt is svm on AMD and vmx on Intel, so only an x86 machine offers it.
NESTED_VIRT = "nested-virt"
CPU_FLAGS = (NESTED_VIRT, "aes")
X86 = "x86_64"
DEFAULT_CPU_MODEL = "AMD EPYC 7763 64-Core Processor"
MAC_CPU_MODEL = "Apple M4"
# What the machine is made of (Facts.hardware), as a Linux helper of this build reads it: a server to go with DEFAULT_CPU_MODEL. The macOS helper does not say it.
DEFAULT_HARDWARE = {
    "system": "Dell PowerEdge R7525",
    "core_types": [{"name": DEFAULT_CPU_MODEL, "cores": 64, "max_mhz": 3529}],
    "disks": [{"model": "Dell Ent NVMe P5600 MU U.2 3.2TB", "size_gb": 3200, "kind": "nvme"}],
}
# The card --nvidia announces, with the details a Linux helper of this build reads from the driver.
RTX_5090 = {"vendor": "nvidia", "model": "NVIDIA GeForce RTX 5090", "memory_mb": 32768, "architecture": "Blackwell", "compute_capability": "12.0",
            "driver_version": "580.178.04", "max_clock_mhz": 3090, "uses_system_memory": False}
# Every CPU setting a helper of this build offers, as --cpu-options turns them on: MachineSpec(**CPU_OPTIONS).
CPU_OPTIONS = {"cpu_models": CPU_MODELS, "cpu_topology": True, "cpu_flags": CPU_FLAGS, "cpu_limit": True}


@dataclass
class MachineSpec:
    os: str = "linux"
    arch: str = "x86_64"
    cpu_cores: int = 16
    # The CPU name the facts announce (cpu_model). None plays an older helper that does not say it: the key is left out.
    cpu_model: str | None = DEFAULT_CPU_MODEL
    # What the machine is made of (Facts.hardware). None plays an older helper, or the macOS one, which do not say it: the key is left out.
    hardware: dict | None = field(default_factory=lambda: copy.deepcopy(DEFAULT_HARDWARE))
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
    gpu_inside: str = "nvidia-smi"
    # A helper of this build can cap and watch the GPU memory of a container; it says so only when containers can use the card at all. False plays an older helper.
    gpu_memory_limit: bool = True
    # The CPU settings a VM can be given (models, more than one socket, flags) and a hard cap on a container's CPU time. The defaults say nothing about them,
    # as every helper did before; CPU_OPTIONS is a helper of this build. The VM settings are offered only with VMs and the cap only with containers.
    cpu_models: tuple = ()
    cpu_topology: bool = False
    cpu_flags: tuple = ()
    cpu_limit: bool = False
    # A helper of this build serves the console and says so in the capabilities. False plays an older helper (no `terminal` entry): the Root still lets an old Mac in, and tells a Linux machine to update.
    terminal: bool = True
    images: list = field(default_factory=lambda: [dict(BLANK_IMAGE)])
    serves_images: bool = True
    # A helper of this build installs apps (OpenClaw, Hermes) into a running VM and says so in GET /v1/images. False plays an older helper: no app entries, no route.
    serves_apps: bool = True
    # What the helper says about the SSH server in a VM after it wrote the keys: running, installed (not running) or missing (the helper had to add it, or could not).
    sshd: str = "running"
    # A helper of this build runs sandboxes (its simulated engine) and says so in its facts: `capabilities.sandbox` and `Facts.sandbox`. False plays a helper
    # from before the sandbox routes, which answers 404 on them and says nothing about sandboxes, so the Root places none on that machine.
    sandbox: bool = False


GPU_OVER_LIMIT_CODE = "gpu_memory_over_limit"


class Refused(Exception):
    """A create the machine cannot take; carries the numbers behind the refusal."""

    def __init__(self, code, message, resource, needed, free):
        super().__init__(message)
        self.code, self.message = code, message
        self.resource, self.needed, self.free = resource, needed, free


class NotFound(Exception):
    pass


class SshdInstallFailed(Exception):
    """The SSH server could not be installed in the VM; the keys were still written."""

    MESSAGE = "The VM could not download the SSH server. Check that the VM has internet access."


class FakeEngine:
    def __init__(self, spec=None, agent_version="fake-1", agent_build=DEFAULT_AGENT_BUILD):
        self.spec = spec or MachineSpec()
        self.agent_version = agent_version
        # The SHA-256 of the program file, as a real helper reports it. None is an older helper that does not say.
        self.agent_build = agent_build
        self.bundle_version = DEFAULT_BUNDLE_VERSION
        self._workloads = {}
        self._commands = {}
        self.create_failure = None
        # Per VM, the complete list of authorized_keys lines the parent last sent, as received.
        self._ssh_keys = {}
        # How many times the parent applied keys, so a test can tell "once" from "again".
        self.ssh_applies = 0
        # The test switch for the install step: "works" or "fails", and how long the step takes.
        self.ssh_install_mode = "works"
        self.ssh_install_delay = 0.0
        self.apps = FakeApps()
        # The pretend sandboxes: records, end times and events, answered the same way a real helper answers them.
        self.sandboxes = FakeSandboxes(self.spec)
        # Every create request this helper accepted, as received, so a test can see what the parent really sent. The CPU settings are only here: the workload list does not carry them.
        self.created_requests = []
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
            **({"cpu_model": spec.cpu_model} if spec.cpu_model is not None else {}),
            **({"hardware": copy.deepcopy(spec.hardware)} if spec.hardware is not None else {}),
            "ram_total_mb": spec.ram_total_mb, "disk_total_gb": spec.disk_total_gb,
            "free_ram_mb": self._free_ram(), "free_disk_gb": self._free_disk(),
            "gpu": list(spec.gpu),
            "capabilities": {
                "vm": spec.vm, "container": spec.container,
                "gpu_in_vm": spec.gpu_in_vm, "gpu_in_container": spec.gpu_in_container,
                "gpu_memory_limit": spec.gpu_in_container and spec.gpu_memory_limit,
                **self._cpu_offer(),
                **({"terminal": True} if spec.terminal else {}),
                "sandbox": spec.sandbox,
            },
            **({"sandbox": self.sandboxes.facts()} if spec.sandbox else {}),
            "agent_version": self.agent_version,
            "engine": {"name": ENGINE_NAME, "version": ENGINE_VERSION, "ready": True},
            **({"agent_build": self.agent_build} if self.agent_build is not None else {}),
        }

    def cpu_offer(self):
        """The CPU settings this helper offers, exactly as its facts announce them."""
        with self._lock:
            return self._cpu_offer()

    def _cpu_offer(self):
        """What is not offered is left out, as a helper from before these settings says nothing (the contract reads that as host only, one socket, no flags, no cap)."""
        spec = self.spec
        offer = {
            "cpu_models": list(spec.cpu_models) if spec.vm else [],
            "cpu_topology": spec.vm and spec.cpu_topology,
            "cpu_flags": [flag for flag in spec.cpu_flags if spec.vm and (flag != NESTED_VIRT or spec.arch == X86)],
            "cpu_limit": spec.container and spec.cpu_limit,
        }
        return {name: value for name, value in offer.items() if value}

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

    def images(self):
        """The images this machine has prepared. Only catalog ids are named."""
        apps = APP_IMAGES if self.spec.serves_apps else []
        return {"images": [dict(image) for image in [*self.spec.images, *apps]]}

    def gpu_check(self, workload_id):
        """What the helper would find inside: nothing is asked of a VM or of a container that was not given the GPU."""
        with self._lock:
            workload = self._get(workload_id)
            if workload["kind"] != "container" or workload["gpu_mode"] != "container":
                return dict(NOT_GIVEN)
            if workload["state"] != "running":
                raise Refused("not_running", "start it first: the GPU can only be checked inside a running container", "state", 1, 0)
            return dict(GPU_INSIDE[self.spec.gpu_inside])

    def ssh_keys_of(self, workload_id):
        """The keys now in the VM's root authorized_keys (what the last apply left there)."""
        with self._lock:
            self._get(workload_id)
            return list(self._ssh_keys.get(workload_id, []))

    def command(self, command_id):
        with self._lock:
            found = self._commands.get(command_id)
            if found is None:
                raise NotFound(command_id)
            return dict(found)

    # ---- write side ------------------------------------------------
    def quit_by_itself(self, workload_id, exit_code, log_tail):
        """Makes a VM stop on its own, as if its first process had quit, and gives the reason a real helper would have found."""
        with self._lock:
            workload = self._get(workload_id)
            workload.update(state="stopped", stopped_reason={"exit_code": exit_code, "log_tail": log_tail})

    def report_gpu_usage(self, workload_id, used_gb):
        """The watchdog's test hook: a container that uses more GPU memory than its limit is stopped, with the reason a real helper reports."""
        with self._lock:
            workload = self._get(workload_id)
            limit = workload.get("gpu_memory_gb")
            if limit is None or used_gb <= limit or workload["state"] != "running":
                return False
            workload.update(state="stopped", stopped_reason={
                "code": GPU_OVER_LIMIT_CODE, "used_gb": used_gb, "limit_gb": limit,
                "message": f"The container used {used_gb:g} GB of GPU memory and its limit is {limit} GB, so it was stopped.",
            })
            return True

    def set_sshd(self, state):
        """What every later apply reports about the VM's SSH server (running, installed or missing)."""
        with self._lock:
            self.spec.sshd = state

    def set_ssh_install(self, mode, delay_seconds):
        """How a later install_sshd call goes: mode "works" or "fails", and how many seconds the install step waits."""
        with self._lock:
            self.ssh_install_mode = mode
            self.ssh_install_delay = float(delay_seconds)

    def apply_ssh_keys(self, workload_id, keys, install_sshd=False):
        """Replaces the whole list in a running VM (an empty list removes every managed key) and says how many are there and what sshd is doing.
        With install_sshd the keys are stored first, then a missing or stopped SSH server is installed and started (or the install fails)."""
        with self._lock:
            workload = self._get(workload_id)
            if workload["state"] != "running":
                raise Refused("not_running", "the VM is not running: start it first", "state", 1, 0)
            self._ssh_keys[workload_id] = list(keys)
            self.ssh_applies += 1
            if not install_sshd:
                return {"applied": len(keys), "sshd": self.spec.sshd}
            before, delay = self.spec.sshd, self.ssh_install_delay
        if before == "missing":
            time.sleep(delay)
        return self._finish_ssh_install(len(keys), before)

    def _finish_ssh_install(self, applied, before):
        with self._lock:
            if before == "missing" and self.ssh_install_mode == "fails":
                raise SshdInstallFailed(SshdInstallFailed.MESSAGE)
            self.spec.sshd = "running"
            return {"applied": applied, "sshd": "running", "installed": before == "missing"}

    def set_app_install(self, mode, delay_seconds):
        """How a later app install goes: mode "works" or "fails", and how many seconds the installer takes."""
        with self._lock:
            self.apps.set_install(mode, delay_seconds)

    def apps_in(self, workload_id):
        with self._lock:
            self._get(workload_id)
            return self.apps.installed_in(workload_id)

    def install_app(self, workload_id, app):
        """Runs the installer inside a running VM. An app that is there already changes nothing (`installed` false)."""
        with self._lock:
            workload = self._get(workload_id)
            if workload["state"] != "running":
                raise Refused("not_running", "the VM is not running: start it first", "state", 1, 0)
            if self.apps.already_there(workload_id, app):
                return self.apps.answer(app, False)
            delay = self.apps.delay_seconds
        time.sleep(delay)
        with self._lock:
            return self.apps.finish_installer(workload_id, app)

    def fail_creates_with(self, message):
        """Every later create fails with this plain-words reason (None: creates work again)."""
        with self._lock:
            self.create_failure = message

    def create(self, body):
        with self._lock:
            existing = self._commands.get(body["command_id"])
            if existing is not None:
                return dict(existing)
            self._check_room(body)
            self.created_requests.append(dict(body))
            if self.create_failure is not None:
                return self._fail(body["command_id"], "create", self.create_failure)
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
        if not gpu_ok and gpu_mode == "container" and kind == "container":
            raise Refused("missing_capability", NO_TOOLKIT_MESSAGE if self.spec.gpu else NO_GPU_MESSAGE, "capability", 1, 0)
        if not gpu_ok:
            raise Refused("missing_capability", f"gpu mode {gpu_mode} is not available here", "capability", 1, 0)

    def _new_workload(self, body):
        return {
            "id": f"wl-{next(self._ids)}", "name": body["name"], "kind": body["kind"], "state": "running",
            "cpu": body["cpu"], "ram_mb": body["ram_mb"], "disk_gb": body["disk_gb"],
            "gpu_mode": body.get("gpu_mode", "none"), "address": None, "bundle_version": None,
            "gpu_memory_gb": body.get("gpu_memory_gb"),
        }

    def set_state(self, command_id, workload_id, command_type, state):
        with self._lock:
            existing = self._commands.get(command_id)
            if existing is not None:
                return dict(existing)
            workload = self._get(workload_id)
            workload["state"] = state
            workload.pop("stopped_reason", None)
            return self._finish(command_id, command_type, workload_id, {"state": state})

    def delete(self, command_id, workload_id):
        with self._lock:
            existing = self._commands.get(command_id)
            if existing is not None:
                return dict(existing)
            self._get(workload_id)
            del self._workloads[workload_id]
            self._ssh_keys.pop(workload_id, None)
            self.apps.forget(workload_id)
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
            return self._finish(body["command_id"], "bundle_install", target, {"version": body["version"], "port": "9200", "chat_key": "fake-key-" + body["version"]})

    def uninstall_bundle(self, body):
        """Turns the chat off. The folder with its conversations is kept, so a later install brings them back."""
        with self._lock:
            existing = self._commands.get(body["command_id"])
            if existing is not None:
                return dict(existing)
            target = body.get("workload_id")
            if target is None:
                self.bundle_version = None
            else:
                self._get(target)["bundle_version"] = None
            return self._finish(body["command_id"], "bundle_uninstall", target, {"kept": KEPT_CHAT_DATA})

    def _get(self, workload_id):
        found = self._workloads.get(workload_id)
        if found is None:
            raise NotFound(workload_id)
        return found

    def _fail(self, command_id, command_type, reason):
        record = {"command_id": command_id, "type": command_type, "state": "failed", "result": {"error": reason}}
        self._commands[command_id] = record
        return dict(record)

    def _finish(self, command_id, command_type, workload_id, result):
        record = {"command_id": command_id, "type": command_type, "state": "succeeded", "result": result}
        if workload_id is not None:
            record["workload_id"] = workload_id
        self._commands[command_id] = record
        return dict(record)
