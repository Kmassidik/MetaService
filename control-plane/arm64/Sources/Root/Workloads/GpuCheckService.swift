import Foundation
import MSCore
import RootCore
import RootStore

/// "Check the GPU inside": asks a machine's helper to look inside one running container for the GPU. Read-only. The answer is checked against the contract's shape and cut again here.
final class GpuCheckService: Sendable {
    static let helperTimeoutSeconds: TimeInterval = 20
    /// One check per workload in this many seconds, however many tabs or clicks ask.
    static let secondsBetweenChecks: TimeInterval = 5
    private static let missingRouteStatus = 404
    private static let notRunningStatus = 409

    private let machines: MachineStore
    private let client: AgentClient
    private let throttle: Throttle
    private let clock: Clock

    init(machines: MachineStore, client: AgentClient, throttle: Throttle, clock: Clock) {
        self.machines = machines
        self.client = client
        self.throttle = throttle
        self.clock = clock
    }

    func check(machine: String, workload: String) async throws -> GpuCheckReply {
        let summary: MachineSummary
        do {
            summary = try machines.get(id: machine, now: clock.now)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        guard let found = summary.workloads.first(where: { $0.id == workload }) else { throw ApiFailure.notFound }
        guard GpuCheckReply.canHaveGpu(kind: found.kind, gpuMode: found.gpuMode) else { return .notGiven }
        guard summary.state != "offline" else { throw Self.unreachable("the machine is offline") }
        guard found.state == "running" else { throw ApiFailure(status: .conflict, code: "not_running", message: "start it first: the GPU can only be checked inside a running container") }
        guard throttle.allow("gpu-check:\(machine)/\(workload)", limit: 1, seconds: Self.secondsBetweenChecks) else { throw ApiFailure.tooMany }
        return try await ask(machine: machine, workload: workload)
    }

    private func ask(machine: String, workload: String) async throws -> GpuCheckReply {
        guard let reply = try? await client.call(machine: machine, method: "POST", path: "/v1/workloads/\(workload)/gpu-check", timeout: Self.helperTimeoutSeconds) else {
            throw Self.unreachable("the machine did not answer")
        }
        switch reply.status {
        case 200:
            guard let parsed = GpuCheckReply.parse(reply.json) else { throw Self.unreachable("the machine answered in a way the parent cannot read") }
            return parsed
        case Self.missingRouteStatus: throw ApiFailure(status: .conflict, code: "not_supported", message: "this machine's helper is too old to check the GPU: update the helper first")
        case Self.notRunningStatus: throw ApiFailure(status: .conflict, code: "not_running", message: "start it first: the GPU can only be checked inside a running container")
        default: throw Self.unreachable("the machine could not check it")
        }
    }

    private static func unreachable(_ message: String) -> ApiFailure {
        ApiFailure(status: .badGateway, code: "unreachable", message: message)
    }
}
