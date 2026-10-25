"""What a machine is made of, against a real Root and a fake helper (agent/fake): GET /api/machines and the machine detail carry `hardware` (the computer's
make and model, each kind of CPU core, the drives) as the helper says it, its texts cleaned like cpu_model, replaced by every heartbeat and null for a helper
that does not say it; the GPU details (architecture, compute capability, driver, highest clock, shared memory) come back on gpu[], and a card without them
comes back as before; a heartbeat with a hardware report or a GPU detail the contract does not allow is refused and changes nothing."""
from agent.fake.engine import DEFAULT_HARDWARE, RTX_5090, MachineSpec
from contract.root_tests.checks_cpu_options import heartbeat_of
from contract.root_tests.checks_gpu import CARD, MACHINE, GpuHelper, machine_like, tell_the_parent
from contract.root_tests.checks_monitor import enroll
from contract.root_tests.support import Browser, expect, running

SPARK = {
    "system": "NVIDIA DGX Spark",
    "core_types": [{"name": "Cortex-X925", "cores": 10, "max_mhz": 4004}, {"name": "Cortex-A725", "cores": 10, "max_mhz": 2860}],
    "disks": [{"model": "ESL04TBTLCZ-27J2-TYN", "size_gb": 4096, "kind": "nvme"}],
}
# The DGX Spark's GPU works in the machine's memory, so it has no memory_mb.
SPARK_GPU = {"vendor": "nvidia", "model": "NVIDIA GB10", "architecture": "Blackwell", "compute_capability": "12.1", "driver_version": "580.95.05",
             "max_clock_mhz": 3003, "uses_system_memory": True}
HOSTILE_HARDWARE = {
    "control characters": ({"system": "  ASUS\tROG\x00  CROSSHAIR\x1b[31m \n VIII "}, {"system": "ASUS ROG CROSSHAIR[31m VIII"}),
    "300 characters": ({"core_types": [{"name": "Z" * 300, "cores": 8}]}, {"core_types": [{"name": "Z" * 120, "cores": 8}]}),
    "html": ({"disks": [{"model": "<img src=x onerror=alert(1)>", "size_gb": 1000, "kind": "ssd"}]},
             {"disks": [{"model": "<img src=x onerror=alert(1)>", "size_gb": 1000, "kind": "ssd"}]}),
    "a name of only blanks": ({"system": "Raspberry Pi 4 Model B Rev 1.5", "core_types": [{"name": " \t\n ", "cores": 4}, {"name": "Cortex-A72", "cores": 4, "max_mhz": 1800}]},
                              {"system": "Raspberry Pi 4 Model B Rev 1.5", "core_types": [{"name": "Cortex-A72", "cores": 4, "max_mhz": 1800}]}),
    "nothing left": ({"system": "\t", "disks": [{"model": " ", "size_gb": 32, "kind": "ssd"}]}, None),
}
BROKEN_HARDWARE = {
    "an unknown key": {**DEFAULT_HARDWARE, "serial": "ABC123"},
    "an unknown key on a core type": {"core_types": [{"name": "Cortex-A72", "cores": 4, "threads": 4}]},
    "an unknown key on a drive": {"disks": [{"model": "WDC WD40EFRX", "size_gb": 4000, "kind": "hdd", "serial": "WD-1"}]},
    "no cores": {"core_types": [{"name": "Cortex-A72", "cores": 0}]},
    "a core type without a name": {"core_types": [{"cores": 4}]},
    "a clock out of range": {"core_types": [{"name": "Cortex-A72", "cores": 4, "max_mhz": 20001}]},
    "a drive kind the contract does not know": {"disks": [{"model": "SanDisk Ultra", "size_gb": 64, "kind": "usb"}]},
    "a size as text": {"disks": [{"model": "WDC WD40EFRX", "size_gb": "4 TB", "kind": "hdd"}]},
    "nine drives": {"disks": [{"model": "WDC WD40EFRX", "size_gb": 4000, "kind": "hdd"}] * 9},
    "an empty list": {"core_types": []},
    "a system that is not text": {"system": 7525},
    "a list, not an object": [DEFAULT_HARDWARE],
}
BROKEN_GPU = {
    "an unknown key": {"pcie_gen": 5},
    "an architecture of 33 characters": {"architecture": "B" * 33},
    "a compute capability of the wrong shape": {"compute_capability": "sm_120"},
    "a driver version with a space": {"driver_version": "580 178"},
    "markup as a driver version": {"driver_version": "<b>580</b>"},
    "a clock out of range": {"max_clock_mhz": 0},
    "shared memory as text": {"uses_system_memory": "yes"},
}


def listed(operator, machine=MACHINE):
    """The machine as GET /api/machines shows it; the machine detail must show the same hardware and GPUs."""
    machine_listed = next(m for m in operator.request("GET", "/api/machines").body["machines"] if m["id"] == machine)
    expect("hardware" in machine_listed, f"hardware must always be in the machine object: {sorted(machine_listed)}")
    detail = operator.request("GET", f"/api/machines/{machine}").body
    expect("hardware" in detail and detail["hardware"] == machine_listed["hardware"] and detail["gpu"] == machine_listed["gpu"],
           f"the detail must say what the list says: {detail.get('hardware', 'missing')!r} {detail['gpu']!r}")
    return machine_listed


def check_what_the_machine_is_made_of_is_kept_cleaned_and_null_for_a_helper_that_does_not_say():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec())
        try:
            beat()
            seen = listed(operator)["hardware"]
            expect(seen == DEFAULT_HARDWARE, f"the hardware as the helper says it: {seen!r}")
            helper.engine.spec = MachineSpec(hardware=SPARK)
            beat()
            seen = listed(operator)["hardware"]
            expect(seen == SPARK, f"the next heartbeat replaces it: {seen!r}")
            for label, (sent, wanted) in HOSTILE_HARDWARE.items():
                helper.engine.spec = MachineSpec(hardware=sent)
                beat()
                seen = listed(operator)["hardware"]
                expect(seen == wanted, f"{label}: wanted {wanted!r}, got {seen!r}")
            helper.engine.spec = MachineSpec(hardware=None)
            beat()
            expect(listed(operator)["hardware"] is None, "a helper that does not say it must show null, not the last answer")
        finally:
            helper.stop()


def check_the_gpu_details_come_back_on_gpu_and_a_card_without_them_comes_back_as_before():
    with running() as root:
        operator = Browser(root)
        helper, beat = machine_like(operator, root, MachineSpec(vm=False, gpu=[RTX_5090], gpu_in_container=True))
        try:
            beat()
            seen = listed(operator)["gpu"]
            expect(seen == [RTX_5090], f"the card with its details: {seen!r}")
            helper.engine.spec = MachineSpec(gpu=[SPARK_GPU], hardware=SPARK)
            beat()
            seen = listed(operator)["gpu"]
            expect(seen == [SPARK_GPU], f"a GPU that works in the machine's memory, without memory_mb: {seen!r}")
            helper.engine.spec = MachineSpec(vm=False, gpu=[CARD], gpu_in_container=True)
            beat()
            seen = listed(operator)["gpu"]
            expect(seen == [CARD], f"an older helper's card comes back as before: {seen!r}")
        finally:
            helper.stop()


def check_a_heartbeat_with_hardware_or_gpu_details_the_contract_does_not_allow_is_refused_and_changes_nothing():
    with running() as root:
        operator = Browser(root)
        machine_token, command_token = enroll(operator, MACHINE)
        helper = GpuHelper(command_token, MachineSpec(vm=False, gpu=[RTX_5090], gpu_in_container=True))
        try:
            tell_the_parent(root, machine_token, helper)
            before = listed(operator)
            cases = [(f"hardware: {label}", {"hardware": hardware}) for label, hardware in BROKEN_HARDWARE.items()]
            cases += [(f"gpu: {label}", {"gpu": [{**RTX_5090, **change}]}) for label, change in BROKEN_GPU.items()]
            for label, change in cases:
                body = heartbeat_of(helper)
                body["facts"].update(change)
                reply = Browser(root).request("POST", "/v1/agents/heartbeat", body, headers={"Authorization": f"Bearer {machine_token}"}, origin=None)
                expect(reply.status == 400, f"{label}: wanted a refusal, got {reply.status}")
            after = listed(operator)
            expect((after["hardware"], after["gpu"], after["last_seen"]) == (before["hardware"], before["gpu"], before["last_seen"]),
                   f"a refused heartbeat changed the machine: {after['hardware']!r} {after['gpu']!r}")
        finally:
            helper.stop()


CHECKS = [check_what_the_machine_is_made_of_is_kept_cleaned_and_null_for_a_helper_that_does_not_say,
          check_the_gpu_details_come_back_on_gpu_and_a_card_without_them_comes_back_as_before,
          check_a_heartbeat_with_hardware_or_gpu_details_the_contract_does_not_allow_is_refused_and_changes_nothing]
