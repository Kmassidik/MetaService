import Foundation

/// An engine that only pretends. Used to test the Agent on a machine that has no virtualization tool, and by the conformance suite.
public actor SimulatedEngine: Engine {
    public nonisolated let capabilities: Capabilities
    private var store: [String: Workload] = [:]

    public init(capabilities: Capabilities = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false)) {
        self.capabilities = capabilities
    }

    public func list() async throws -> [Workload] {
        Array(store.values)
    }

    public func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
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

    public func setBundleVersion(id: String, version: String) async throws {
        try change(id) { $0.bundleVersion = version }
    }

    private func change(_ id: String, _ edit: (inout Workload) -> Void) throws {
        guard var found = store[id] else { throw EngineError.notFound }
        edit(&found)
        store[id] = found
    }
}
