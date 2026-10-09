import Foundation

/// What an Agent needs from the machine's virtualization layer. One implementation per OS; the Agent logic above it is shared.
public protocol Engine: Sendable {
    var capabilities: Capabilities { get }
    func list() async throws -> [Workload]
    func create(id: String, request: CreateWorkloadRequest) async throws -> Workload
    func setRunning(id: String, running: Bool) async throws
    /// Copies the workload's disk somewhere safe and returns the backup's name. Called before every delete.
    func backup(id: String) async throws -> String
    func delete(id: String) async throws
    /// Records which chat bundle version a workload has.
    func setBundleVersion(id: String, version: String) async throws
    /// Copies a file from this machine into the workload.
    func push(id: String, hostPath: String, containerPath: String) async throws
    /// Runs one program inside the workload (no shell is added) and returns what it printed. Values go in through `environment`, never into the arguments.
    func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String
}

public enum EngineError: Error, Equatable {
    case notFound
    case failed(String)
}
