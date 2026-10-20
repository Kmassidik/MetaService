import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// Add machine for another computer: what will change, the install and its steps, the machines installed this way, and taking one away.
struct RemoteInstallRoutes {
    let services: Services
    let guards: Guards

    static let planPerMinute = 20
    static let installsPerMinute = 3
    static let removalsPerMinute = 6

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/remote/plan", use: plan)
        group.post("/api/remote/installs", use: start)
        group.get("/api/remote/installs/{id}", use: progress)
        group.get("/api/remote/machines", use: machines)
        group.post("/api/remote/machines/{name}/remove", use: remove)
    }

    func plan(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorWrite(request)
        try guards.limit("remote-plan", per: context, max: Self.planPerMinute, seconds: 60)
        let body = try await parsed(request) { try PlanRequest(body: $0) }
        return try answer { try Json.response(services.remoteInstalls.plan(body)) }
    }

    func start(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("remote-install", per: context, max: Self.installsPerMinute, seconds: 60)
        let body = try await parsed(request) { try RemoteAddRequest(body: $0) }
        return try answer { try Json.response(Started(id: services.remoteInstalls.start(body, actor: caller.name)), status: .accepted) }
    }

    func progress(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        guard let id = context.parameters.get("id"), let job = services.remoteInstalls.job(id) else { throw ApiFailure.notFound }
        return try Json.response(job)
    }

    func machines(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try Json.response(Listed(machines: try services.remoteMachines.all().map { Listed.Entry($0, tunnel: services.tunnels.status(of: $0.machine)) }))
    }

    func remove(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("remote-remove", per: context, max: Self.removalsPerMinute, seconds: 60)
        guard let name = context.parameters.get("name"), Ids.isValid(name) else { throw ApiFailure.notFound }
        let body = try await parsed(request) { try RemoteRemoveRequest(body: $0) }
        do {
            try await services.remoteInstalls.remove(machine: name, request: body, actor: caller.name)
        } catch let failure as RemoteFailure {
            throw failure.api
        } catch let failure as InstallFailure {
            throw ApiFailure(status: .badGateway, code: "remote_removal_failed", message: failure.message)
        }
        services.screens.closeAll(machine: name)
        return Response(status: .noContent)
    }

    private func parsed<T>(_ request: Request, _ make: (Data) throws -> T) async throws -> T {
        do { return try make(try await guards.body(request)) } catch let error as InputError { throw ApiFailure.invalid(error.message) }
    }

    private func answer(_ work: () throws -> Response) throws -> Response {
        do { return try work() } catch let failure as RemoteFailure { throw failure.api }
    }
}

private struct Started: Encodable { let id: String }

private struct Listed: Encodable {
    struct Entry: Encodable {
        let machine: String, host: String, sshPort: Int, sshUser: String, level: String, box: String, agentPort: Int, engine: String, hasKey: Bool
        let tunnel: TunnelStatus?

        init(_ record: RemoteMachine, tunnel: TunnelStatus?) {
            self.tunnel = tunnel
            machine = record.machine
            host = record.host
            sshPort = record.sshPort
            sshUser = record.sshUser
            level = record.level
            box = record.box
            agentPort = record.agentPort
            engine = record.engine
            hasKey = record.keyName != nil
        }
    }

    let machines: [Entry]
}
