import Foundation

/// What an Agent needs from the machine's virtualization layer. One implementation per OS; the Agent logic above it is shared.
public protocol Engine: Sendable {
    var capabilities: Capabilities { get }
    /// What this engine is, for the facts: a short name and its version, or nil when it cannot tell. Never guessed.
    func identity() async -> EngineIdentity
    /// What on this machine stops it from running workloads right now. Empty means ready.
    var problems: [HostProblem] { get }
    func list() async throws -> [Workload]
    func create(id: String, request: CreateWorkloadRequest) async throws -> Workload
    func setRunning(id: String, running: Bool) async throws
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    func backup(id: String) async throws -> String
    func delete(id: String) async throws
    /// Records which chat bundle version a workload has (nil: none, the chat was turned off).
    func setBundleVersion(id: String, version: String?) async throws
    /// Copies a file from this machine into the workload.
    func push(id: String, hostPath: String, containerPath: String) async throws
    /// Runs one program inside the workload (no shell is added) and returns what it printed. Values go in through `environment`, never into the arguments.
    func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String
    /// The program and arguments that open an interactive shell inside the workload, to be run in a pty. The first item is the program. No shell string, no user text.
    func attach(id: String) async throws -> [String]
}

/// The name and version of the program a machine makes VMs with.
public struct EngineIdentity: Equatable, Sendable {
    public let name: String
    public let version: String?

    public init(name: String, version: String?) {
        self.name = name
        self.version = version
    }
}

public extension Engine {
    var problems: [HostProblem] { [] }
}

public enum EngineError: Error, Equatable {
    case notFound
    case failed(String)
    /// The VM was made but never came up. The text is written by the helper (it may hold the last lines the VM printed, cleaned) and is safe to show the person.
    case notReady(String)
}
