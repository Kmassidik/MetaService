import Foundation
import Hummingbird
import RootCore
import RootStore

/// What the control panel calls. Every route needs the operator's session; writes also need the exact Origin and the session's CSRF header.
struct OperatorRoutes {
    let services: Services
    let guards: Guards

    static let defaultAuditPage = 50

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/session", use: session)
        group.get("/api/machines", use: listMachines)
        group.get("/api/machines/{id}", use: getMachine)
        group.delete("/api/machines/{id}", use: removeMachine)
        group.post("/api/enrollments", use: createEnrollment)
        group.get("/api/audit", use: audit)
    }

    func session(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorRead(request)
        return try Json.response(SessionReply(username: caller.name, csrfToken: caller.csrfToken))
    }

    func listMachines(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try Json.response(MachineList(machines: try services.machines.list(now: services.clock.now)))
    }

    func getMachine(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let id = try machineId(context)
        do {
            return try Json.response(try services.machines.get(id: id, now: services.clock.now))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }

    func removeMachine(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try machineId(context)
        do {
            try services.machines.remove(id: id)
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
        try services.chatAccess.remove(target: id)
        try services.audit.record(actor: caller.name, action: "machine.remove", target: id, at: services.clock.now)
        return Response(status: .noContent)
    }

    func createEnrollment(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let body = try CreateEnrollmentRequest(body: try await guards.body(request))
        let made: (token: String, expires: Date)
        do {
            made = try services.enrollments.create(machineName: body.name, expectedIp: body.expectedIp, now: services.clock.now)
        } catch EnrollmentError.machineExists {
            throw ApiFailure(status: .conflict, code: "machine_exists", message: "a machine with that name is already enrolled")
        }
        try services.audit.record(actor: caller.name, action: "enrollment.create", target: body.name, at: services.clock.now)
        let reply = EnrollmentReply(name: body.name, enrollmentToken: made.token, expiresAt: ISO8601DateFormatter().string(from: made.expires))
        return try Json.response(reply, status: .created)
    }

    func audit(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let limit = request.uri.queryParameters.get("limit", as: Int.self) ?? Self.defaultAuditPage
        let before = request.uri.queryParameters.get("before", as: Int.self)
        return try Json.response(AuditList(entries: try services.audit.list(limit: limit, before: before)))
    }

    private func machineId(_ context: RootContext) throws -> String {
        guard let id = context.parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return id
    }
}

private struct SessionReply: Encodable {
    let username: String
    let csrfToken: String
}

private struct MachineList: Encodable {
    let machines: [MachineSummary]
}

private struct EnrollmentReply: Encodable {
    let name: String
    let enrollmentToken: String
    let expiresAt: String
}

private struct AuditList: Encodable {
    let entries: [AuditEntry]
}
