import Foundation
import RootCore
import RootStore

/// The JSON a tool answers with for machines and VMs. A missing value is JSON null, so the shape never changes.
extension McpService {
    static func null(_ value: Any?) -> Any { value ?? NSNull() }

    func machineView(_ machine: MachineSummary) -> [String: Any] {
        let card = machine.gpu.first.map { gpu -> [String: Any] in
            ["name": gpu.model, "total_gb": Self.null(GpuBooking.totalGb(gpu: machine.gpu)), "free_gb": Self.null(machine.gpuBooking?.freeGb)]
        }
        return ["id": machine.id, "name": machine.name, "state": machine.state, "os": Self.null(machine.os), "arch": Self.null(machine.arch), "shared": isShared(machine),
                "cpu_cores": Self.null(machine.cpuCores), "ram_total_mb": Self.null(machine.ramTotalMb), "free_ram_mb": Self.null(machine.freeRamMb),
                "free_disk_gb": Self.null(machine.freeDiskGb), "gpu": Self.null(card), "engine_ready": machine.engine?.ready ?? false]
    }

    func vmView(_ vm: WorkloadSummary, on machine: MachineSummary) -> [String: Any] {
        ["machine": machine.id, "id": vm.id, "name": vm.name, "state": vm.state, "vcpu": vm.cpu, "ram_mb": vm.ramMb, "disk_gb": vm.diskGb,
         "gpu_memory_gb": Self.null(vm.gpuMemoryGb), "address": Self.null(vm.address), "created_by_me": true]
    }

    /// vm_status and every finished request: the VM plus how to log in and, for a VM that stopped by itself, why.
    func vmDetail(_ vm: WorkloadSummary, on machine: MachineSummary) -> [String: Any] {
        var view = vmView(vm, on: machine)
        view["ssh_command"] = Self.null(vm.address == nil ? nil : (try? sshKeys.view(machine: machine.id, workload: vm.id))?.connect.command)
        view["stopped_reason"] = Self.null(vm.stoppedReason.flatMap { $0.message ?? $0.code })
        return view
    }

    /// A VM still being made has no id yet: it is listed by its request so the AI can follow it.
    func creatingView(_ row: McpWorkloadRow) -> [String: Any] {
        ["machine": row.machineId, "id": NSNull(), "name": NSNull(), "state": "creating", "vcpu": row.vcpu, "ram_mb": row.ramMb, "disk_gb": row.diskGb,
         "gpu_memory_gb": NSNull(), "address": NSNull(), "created_by_me": true, "request_id": row.requestId]
    }

    /// The VM a row of this token stands for, as the machine reports it now. Nil when the machine does not (yet) list it.
    func liveVm(_ row: McpWorkloadRow) -> (vm: WorkloadSummary, machine: MachineSummary)? {
        guard let id = row.workloadId, let machine = try? machines.get(id: row.machineId, now: clock.now),
              let vm = machine.workloads.first(where: { $0.id == id }) else { return nil }
        return (vm, machine)
    }
}
