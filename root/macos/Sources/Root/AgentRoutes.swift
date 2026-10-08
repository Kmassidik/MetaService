import Foundation
import Hummingbird
import RootCore
import RootStore

/// The Root half of the contract: Agents enroll and send heartbeats.
struct AgentRoutes {
    let services: Services
    let guards: Guards

    static let enrollPerMinute = 10

    func register(on group: RouterGroup<RootContext>) {
        group.post("/v1/agents/enroll", use: enroll)
        group.post("/v1/agents/heartbeat", use: heartbeat)
    }

    func enroll(_ request: Request, context: RootContext) async throws -> Response {
        try guards.limit("enroll", per: context, max: Self.enrollPerMinute, seconds: 60)
        let body = try EnrollRequest(body: try await guards.body(request))
        let now = services.clock.now
        guard try services.enrollments.consume(token: body.enrollmentToken, machineName: body.name, fromIp: context.remoteIP, now: now) else {
            try services.audit.record(actor: "agent:\(body.name)", action: "machine.enroll_refused", detail: ["from": context.remoteIP], at: now)
            throw ApiFailure.unauthorized("enrollment refused")
        }
        let machineToken = Tokens.random()
        try services.machines.enroll(name: body.name, tokenHash: Tokens.sha256Hex(machineToken), ip: context.remoteIP, now: now)
        try services.audit.record(actor: "agent:\(body.name)", action: "machine.enroll", target: body.name, detail: ["from": context.remoteIP], at: now)
        return try Json.response(EnrollReply(machineToken: machineToken, heartbeatSeconds: MachineStates.heartbeatSeconds))
    }

    func heartbeat(_ request: Request, context: RootContext) async throws -> Response {
        let machineId = try guards.machine(request, context: context)
        let beat = try HeartbeatRequest(body: try await guards.body(request))
        try services.machines.recordHeartbeat(machineId: machineId, request: beat, ip: context.remoteIP, now: services.clock.now)
        return Response(status: .noContent)
    }
}

private struct EnrollReply: Encodable {
    let machineToken: String
    let heartbeatSeconds: Int
}
