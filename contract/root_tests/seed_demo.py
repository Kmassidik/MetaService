"""Fill a running Root with demo machines, so the panel can be looked at.
Usage: python3 -m contract.root_tests.seed_demo http://localhost:9100 http://127.0.0.1:9102   (operator listener, then Agent listener)"""
import sys

from contract.root_tests.support import Browser, good_heartbeat


class Remote:
    """Enough of a RunningRoot for Browser, for a Root that is already running."""

    def __init__(self, base, agent_base):
        self.base = base
        self.port = int(base.rsplit(":", 1)[1])
        self.agent_port = int(agent_base.rsplit(":", 1)[1])


MACHINES = {
    "mac-studio": dict(os="macos", arch="arm64", cores=24, ram=196608, disk=3800, free_ram=90000, free_disk=2100, gpu=[],
                       caps=(True, False, False, False), workloads=[("vm-owner", "vm", "running", 4, 16384, 120), ("vm-demo", "vm", "stopped", 2, 8192, 60)]),
    "dgx-spark": dict(os="linux", arch="aarch64", cores=20, ram=131072, disk=3800, free_ram=61000, free_disk=3000,
                      gpu=[{"vendor": "nvidia", "model": "GB10", "memory_mb": 131072}], caps=(True, True, False, True),
                      workloads=[("gpu-runner", "container", "running", 8, 65536, 200)]),
    "mac-mini": dict(os="macos", arch="arm64", cores=10, ram=32768, disk=228, free_ram=20000, free_disk=60, gpu=[],
                     caps=(True, False, False, False), workloads=[("fresh-vm", "vm", "provisioning", 2, 4096, 50)]),
}


def heartbeat(spec):
    vm, container, gpu_vm, gpu_container = spec["caps"]
    body = good_heartbeat()
    body["facts"].update(os=spec["os"], arch=spec["arch"], cpu_cores=spec["cores"], ram_total_mb=spec["ram"], disk_total_gb=spec["disk"],
                         free_ram_mb=spec["free_ram"], free_disk_gb=spec["free_disk"], gpu=spec["gpu"],
                         capabilities={"vm": vm, "container": container, "gpu_in_vm": gpu_vm, "gpu_in_container": gpu_container})
    body["workloads"] = [{"id": f"wl-{i}", "name": name, "kind": kind, "state": state, "cpu": cpu, "ram_mb": ram, "disk_gb": disk,
                          "gpu_mode": "container" if "gpu" in name else "none", "address": f"192.168.64.{i + 10}" if kind == "vm" else None,
                          "bundle_version": "1.0.0"} for i, (name, kind, state, cpu, ram, disk) in enumerate(spec["workloads"], 1)]
    return body


def main(base, agent_base):
    operator = Browser(Remote(base, agent_base))
    for name, spec in MACHINES.items():
        invite = operator.write("POST", "/api/enrollments", {"name": name})
        token = Browser(Remote(base, agent_base)).request("POST", "/v1/agents/enroll", {"enrollment_token": invite.body["enrollment_token"], "name": name}, origin=None).body["machine_token"]
        Browser(Remote(base, agent_base)).request("POST", "/v1/agents/heartbeat", heartbeat(spec), headers={"Authorization": f"Bearer {token}"}, origin=None)
    operator.write("POST", "/api/enrollments", {"name": "pc-itx"})
    print("seeded", ", ".join(MACHINES), "(pc-itx invited only)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
