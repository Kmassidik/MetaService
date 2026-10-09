import Foundation

/// Stands in when the machine cannot run workloads yet (for example the container tool is not installed). The Agent still runs, reports the machine's
/// real facts and the problem with its fix, and refuses every workload, so the panel can show the machine and say what is missing.
public struct UnavailableEngine: Engine {
    public let problem: HostProblem
    public var capabilities: Capabilities { Capabilities(vm: false, container: false, gpuInVm: false, gpuInContainer: false) }
    public var problems: [HostProblem] { [problem] }

    public init(problem: HostProblem) {
        self.problem = problem
    }

    public func list() async throws -> [Workload] { [] }
    public func create(id: String, request: CreateWorkloadRequest) async throws -> Workload { throw unavailable }
    public func setRunning(id: String, running: Bool) async throws { throw EngineError.notFound }
    public func backup(id: String) async throws -> String { throw EngineError.notFound }
    public func delete(id: String) async throws { throw EngineError.notFound }
    public func setBundleVersion(id: String, version: String) async throws { throw EngineError.notFound }
    public func push(id: String, hostPath: String, containerPath: String) async throws { throw EngineError.notFound }
    public func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String { throw EngineError.notFound }

    private var unavailable: EngineError { .failed(problem.message) }
}
