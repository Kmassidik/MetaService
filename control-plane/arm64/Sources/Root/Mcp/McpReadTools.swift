import Foundation
import RootCore
import RootStore

/// The tools that only look: list_machines, machine_capacity, list_vms, vm_status and get_request. They change nothing.
extension McpService {
    func listMachines(caller: McpCaller) throws -> [String: Any] {
        ["machines": try visibleMachines(for: caller).map(machineView)]
    }

    func machineCapacity(_ machineId: String, caller: McpCaller) throws -> [String: Any] {
        let machine = try machine(machineId, for: caller)
        let promised = (try? commands.promised(machine: machine.id)) ?? (ramMb: 0, diskGb: 0)
        let used = machine.workloads.filter { ["running", "provisioning"].contains($0.state) }.reduce(0) { $0 + $1.cpu }
        let freeRam = machine.freeRamMb.map { max(0, $0 - promised.ramMb) }
        let freeDisk = machine.freeDiskGb.map { max(0, $0 - promised.diskGb) }
        let fits = McpSize.presets.filter { Self.fits($0.dimensions, cores: machine.cpuCores, freeRamMb: freeRam, freeDiskGb: freeDisk) }
        return ["machine": machine.id, "free_vcpu": Self.null(machine.cpuCores.map { max(0, $0 - used) }), "free_ram_mb": Self.null(freeRam),
                "free_disk_gb": Self.null(freeDisk), "gpu_free_gb": Self.null(machine.gpuBooking?.freeGb), "sizes_that_fit": fits.map(\.size.rawValue)]
    }

    /// The panel's own rule (vmSize.ts): a number the machine has not reported cannot rule a size out.
    private static func fits(_ size: McpSize.Dimensions, cores: Int?, freeRamMb: Int?, freeDiskGb: Int?) -> Bool {
        size.vcpu <= (cores ?? size.vcpu) && size.ramMb <= (freeRamMb ?? size.ramMb) && size.diskGb <= (freeDiskGb ?? size.diskGb)
    }

    func listVms(machine only: String?, caller: McpCaller) throws -> [String: Any] {
        if let only { _ = try machine(only, for: caller) }
        let mine = try ownership.alive(caller: caller.id).filter { only == nil || $0.machineId == only }
        let listed = mine.map { row in liveVm(row).map { vmView($0.vm, on: $0.machine) } ?? (row.workloadId == nil ? creatingView(row) : nil) }.compactMap { $0 }
        let ownCount = mine.filter { $0.workloadId != nil }.count
        let everything = try visibleMachines(for: caller).filter { only == nil || $0.id == only }.reduce(0) { $0 + $1.workloads.count }
        return ["vms": listed, "others": max(0, everything - ownCount)]
    }

    func vmStatus(machine machineId: String, vm: String, caller: McpCaller) throws -> [String: Any] {
        guard let row = try ownership.find(caller: caller.id, machine: machineId, workload: vm), let live = liveVm(row) else { throw McpRefusal.noVm }
        return vmDetail(live.vm, on: live.machine)
    }

    func getRequest(_ id: String, caller: McpCaller) throws -> [String: Any] {
        guard let request = try requests.get(id: id), request.personId == caller.person.id else { throw McpRefusal.noRequest }
        return requestView(request, caller: caller)
    }

    /// A request as the AI sees it: where it stands, the VM once there is one, the plain reason when it failed.
    func requestView(_ request: McpRequestRow, caller: McpCaller) -> [String: Any] {
        var view: [String: Any] = ["request_id": request.id, "kind": request.kind.rawValue, "status": request.state.rawValue]
        switch request.state {
        case .running: view["message"] = "Still in progress: call get_request again in a few seconds."
        case .failed: view["reason"] = request.result?["message"] as? String ?? "it did not work"
        case .done: view["vm"] = doneVm(request, caller: caller)
        }
        return view
    }

    private func doneVm(_ request: McpRequestRow, caller: McpCaller) -> Any {
        guard let machine = request.result?["machine"] as? String, let vm = request.result?["vm"] as? String else { return NSNull() }
        let row = try? ownership.find(caller: caller.id, machine: machine, workload: vm)
        guard let row, let live = liveVm(row) else { return ["machine": machine, "id": vm, "state": request.kind == .delete ? "deleted" : "unknown"] }
        return vmDetail(live.vm, on: live.machine)
    }
}
