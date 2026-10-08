import Foundation
import Hummingbird
import HTTPTypes
import AgentCore
import MSCore

/// The Agent half of contract/openapi.yaml.
struct AgentRoutes {
    let service: AgentService

    func register(on router: Router<AgentContext>) {
        router.get("/v1/health") { _, _ in try Json.response(await service.health()) }
        router.get("/v1/facts") { _, _ in try Json.response(await service.facts()) }
        router.get("/v1/workloads") { _, _ in try Json.response(WorkloadList(workloads: try await service.workloads())) }
        router.post("/v1/workloads", use: create)
        router.post("/v1/workloads/{id}/start") { request, context in try await self.change(request, context, start: true) }
        router.post("/v1/workloads/{id}/stop") { request, context in try await self.change(request, context, start: false) }
        router.delete("/v1/workloads/{id}", use: delete)
        router.post("/v1/bundle/install", use: installBundle)
        router.get("/v1/commands/{id}", use: command)
    }

    private func create(_ request: Request, context: AgentContext) async throws -> Response {
        let body = try CreateWorkloadRequest(body: try await Self.body(request))
        return try Self.accepted(try await service.create(body))
    }

    private func change(_ request: Request, _ context: AgentContext, start: Bool) async throws -> Response {
        let id = try Self.workloadId(context), commandId = try Self.commandId(request)
        let command = start ? try await service.start(commandId: commandId, id: id) : try await service.stop(commandId: commandId, id: id)
        return try Self.accepted(command)
    }

    private func delete(_ request: Request, context: AgentContext) async throws -> Response {
        try Self.accepted(try await service.delete(commandId: try Self.commandId(request), id: try Self.workloadId(context)))
    }

    private func installBundle(_ request: Request, context: AgentContext) async throws -> Response {
        try Self.accepted(try await service.installBundle(try BundleInstallRequest(body: try await Self.body(request))))
    }

    private func command(_ request: Request, context: AgentContext) async throws -> Response {
        guard let id = context.parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return try Json.response(try await service.command(id))
    }

    // MARK: helpers

    private static func accepted(_ command: Command) throws -> Response {
        try Json.response(Accepted(commandId: command.commandId, state: command.state), status: .accepted)
    }

    private static func workloadId(_ context: AgentContext) throws -> String {
        guard let id = context.parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return id
    }

    /// The caller's command id (so a retry is safe), or a fresh one.
    private static func commandId(_ request: Request) throws -> String {
        guard let sent = request.headers[HTTPField.Name("X-Command-Id")!] else { return "cmd-" + Tokens.random(bytes: 8).lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12) }
        guard Ids.isValid(sent) else { throw InputError("X-Command-Id is not a valid id") }
        return sent
    }

    private static func body(_ request: Request) async throws -> Data {
        if let declared = request.headers[.contentLength].flatMap({ Int($0) }), declared > AgentContext.maxBodyBytes { throw HTTPError(.contentTooLarge) }
        let buffer = try await request.body.collect(upTo: AgentContext.maxBodyBytes)
        return Data(buffer.readableBytesView)
    }
}

private struct WorkloadList: Encodable { let workloads: [Workload] }
private struct Accepted: Encodable { let commandId: String; let state: CommandState }
