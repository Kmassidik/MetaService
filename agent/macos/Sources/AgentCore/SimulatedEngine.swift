import Foundation

/// An engine that only pretends. Used to test the Agent on a machine that has no virtualization tool, and by the conformance suite.
public actor SimulatedEngine: Engine {
    public nonisolated let capabilities: Capabilities
    private var store: [String: Workload] = [:]
    private var createFailure: EngineError?
    /// What was pushed and run, in order, so tests can look.
    public private(set) var pushed: [[String]] = []
    public private(set) var executed: [[String]] = []

    public init(capabilities: Capabilities = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false)) {
        self.capabilities = capabilities
    }

    public static let engineName = "simulated"

    public func identity() async -> EngineIdentity { EngineIdentity(name: Self.engineName, version: nil) }

    public func list() async throws -> [Workload] {
        Array(store.values)
    }

    /// Makes every later create fail with this error, as a machine whose VMs do not start would.
    public func failCreates(_ error: EngineError?) { createFailure = error }

    public func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
        if let createFailure { throw createFailure }
        let made = Workload(id: id, name: request.name, kind: request.kind, state: .running, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb, gpuMode: request.gpuMode)
        store[id] = made
        return made
    }

    public func setRunning(id: String, running: Bool) async throws {
        try change(id) { $0.state = running ? .running : .stopped }
    }

    public func backup(id: String) async throws -> String {
        try change(id) { _ in }
        return "backup-\(id)"
    }

    public func delete(id: String) async throws {
        guard store.removeValue(forKey: id) != nil else { throw EngineError.notFound }
    }

    public func setBundleVersion(id: String, version: String?) async throws {
        try change(id) { $0.bundleVersion = version }
    }

    public func push(id: String, hostPath: String, containerPath: String) async throws {
        guard store[id] != nil else { throw EngineError.notFound }
        pushed.append([id, hostPath, containerPath])
    }

    public func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String {
        guard store[id] != nil else { throw EngineError.notFound }
        executed.append(arguments)
        return ""
    }

    /// Tests type into a plain /bin/sh on this machine.
    public func attach(id: String) async throws -> [String] {
        guard store[id] != nil else { throw EngineError.notFound }
        return [Self.shellPath]
    }

    public static let shellPath = "/bin/sh"

    private func change(_ id: String, _ edit: (inout Workload) -> Void) throws {
        guard var found = store[id] else { throw EngineError.notFound }
        edit(&found)
        store[id] = found
    }
}
