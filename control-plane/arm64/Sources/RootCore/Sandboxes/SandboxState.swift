import Foundation

/// The state of a sandbox as the parent keeps it, the same words the helper uses in `contract/openapi.yaml`, plus `ended`
/// for the moment after it is gone (the helper then no longer lists it).
public enum SandboxState: String, Codable, CaseIterable, Equatable {
    case starting
    case running
    case pausing
    case paused
    case resuming
    case stopping
    case ended

    /// Still alive at the helper: running, starting, or on its way in or out. A paused sandbox is alive but uses nothing.
    public var isAlive: Bool { self != .ended }

    /// Counts against the machine's and the team's running sandboxes, vCPU and memory. A paused sandbox holds neither.
    public var holdsCompute: Bool {
        switch self {
        case .starting, .running, .pausing, .resuming, .stopping: return true
        case .paused, .ended: return false
        }
    }

    /// Holds its disk: everything that still exists, paused included.
    public var holdsDisk: Bool { isAlive }
}

/// Why a sandbox ended. The first five are the helper's own reasons (`SandboxEvents` in contract/openapi.yaml); `failed`
/// is the parent undoing a create that never ran.
public enum SandboxEndReason: String, Codable, CaseIterable, Equatable {
    case deleted
    case timeout
    case outOfMemory = "out_of_memory"
    case crashed
    case helperRestart = "helper_restart"
    case failed
}
