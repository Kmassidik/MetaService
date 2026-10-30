import Foundation

/// The nine tools, the scope each needs and the sentence the AI reads to choose one. Names and scopes follow mcp/SPEC.md section 4.
public enum McpTool: String, CaseIterable, Equatable {
    case listMachines = "list_machines"
    case machineCapacity = "machine_capacity"
    case listVms = "list_vms"
    case vmStatus = "vm_status"
    case createVm = "create_vm"
    case startVm = "start_vm"
    case stopVm = "stop_vm"
    case deleteVm = "delete_vm"
    case getRequest = "get_request"

    public var scope: McpScope {
        switch self {
        case .listMachines, .machineCapacity, .listVms, .vmStatus, .getRequest: return .read
        case .createVm, .startVm, .stopVm: return .create
        case .deleteVm: return .destroy
        }
    }

    public var description: String {
        switch self {
        case .listMachines: return "List the machines that can run VMs, with their free CPU, memory, disk and GPU. Free; use it first to see where a VM can go."
        case .machineCapacity: return "Show what a new VM can still get on one machine and which sizes (small, medium, large) fit. Free; use it before create_vm on a named machine."
        case .listVms: return "List the VMs this token created, with state, size and address. Free; VMs made by others are only counted."
        case .vmStatus: return "Show one VM of this token: state, size, address, the SSH command, and why it stopped if it did. Free."
        case .createVm: return "Create a VM and wait for it to run. Costs a VM against this token's quotas; large, custom-above-medium, GPU or shared-machine VMs need a person to approve in the panel."
        case .startVm: return "Start a stopped VM that this token created. Costs nothing extra; returns the VM when it runs."
        case .stopVm: return "Stop a running VM that this token created. Its disk stays and it still counts against the quotas."
        case .deleteVm: return "Delete a VM that this token created, for good. Always needs a person to approve in the panel unless the token has auto_approve."
        case .getRequest: return "Check a request_id from create_vm, start_vm, stop_vm or delete_vm: waiting for approval, running, done (with the VM) or failed (with the reason)."
        }
    }

    /// The tools that change something: each leaves a request behind that get_request can follow.
    public var changesThings: Bool {
        switch self {
        case .createVm, .startVm, .stopVm, .deleteVm: return true
        default: return false
        }
    }

    public static let names: [String] = allCases.map(\.rawValue)
}
