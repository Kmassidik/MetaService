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
    /// Records which chat bundle version a workload has (until the real installer in task 7 does it).
    func setBundleVersion(id: String, version: String) async throws
}

public enum EngineError: Error, Equatable {
    case notFound
    case failed(String)
}
