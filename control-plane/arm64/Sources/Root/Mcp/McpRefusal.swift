import Foundation
import Hummingbird
import RootCore
import RootStore

/// A tool call that did not run, with the one sentence the AI reads. `kind` is a short word for the audit trail: scope, quota, invalid, not_found, busy, failed.
struct McpRefusal: Error {
    let kind: String
    let message: String

    static func scope(_ message: String) -> McpRefusal { McpRefusal(kind: "scope", message: message) }
    static func quota(_ message: String) -> McpRefusal { McpRefusal(kind: "quota", message: message) }
    static func invalid(_ message: String) -> McpRefusal { McpRefusal(kind: "invalid", message: message) }
    static func busy(_ message: String) -> McpRefusal { McpRefusal(kind: "busy", message: message) }
    static let noMachine = McpRefusal(kind: "not_found", message: "There is no such machine for this person: call list_machines for the ids it can use.")
    static let noVm = McpRefusal(kind: "not_found", message: "There is no such VM for this person: call list_vms for the VMs they created.")
    static let noRequest = McpRefusal(kind: "not_found", message: "There is no such request for this person.")

    /// Turns what the services throw into a sentence the AI can act on. Nothing about the inside of the parent.
    static func from(_ error: Error) -> McpRefusal {
        switch error {
        case let refusal as McpRefusal: return refusal
        case let input as InputError: return .invalid(input.message)
        case let placement as PlacementRefusal: return McpRefusal(kind: "failed", message: placementText(placement))
        case let gpu as GpuBookingRefusal: return McpRefusal(kind: "failed", message: gpu.message)
        case let failure as ApiFailure: return failure.status == .notFound ? .noVm : McpRefusal(kind: "failed", message: failure.message)
        default: return McpRefusal(kind: "failed", message: "The parent could not do that right now. Try again in a minute.")
        }
    }

    private static func placementText(_ refusal: PlacementRefusal) -> String {
        guard refusal.resource != "capability" else { return refusal.message }
        return "\(refusal.message): \(refusal.needed) needed and \(refusal.free) free (\(refusal.resource)). Ask for a smaller size or another machine."
    }
}
