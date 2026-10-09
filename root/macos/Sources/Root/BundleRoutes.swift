import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// The bundle registry for operators, the download for Agents, and the link that opens a chat.
struct BundleRoutes {
    let services: Services
    let guards: Guards

    static let downloadsPerMinute = 60
    private static let versionPattern = #/^\d{1,4}\.\d{1,4}\.\d{1,4}$/#
    private static let platformPattern = #/^(noarch|(macos|linux)-(arm64|aarch64|x86_64))$/#

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/bundles", use: overview)
        group.post("/api/bundles/pin", use: pin)
        group.post("/api/bundles/rollback", use: rollback)
        group.post("/api/machines/{id}/bundle/install", use: install)
        group.get("/api/chat-link", use: chatLink)
        group.get("/v1/bundles/{version}/{platform}", use: download)
    }

    private func overview(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorSession(request)
        return try Json.response(try services.bundles.overview(now: services.clock.now))
    }

    private func pin(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorWrite(request)
        let version = try PinRequest(body: try await guards.body(request)).version
        do {
            try services.bundles.pin(version: version, actor: session.email, now: services.clock.now)
        } catch BundleError.unknownVersion {
            throw ApiFailure.notFound
        }
        try services.audit.record(actor: session.email, action: "bundle.pin", target: version, at: services.clock.now)
        return try Json.response(try services.bundles.overview(now: services.clock.now))
    }

    private func rollback(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorWrite(request)
        let version: String
        do {
            version = try services.bundles.rollback(actor: session.email, now: services.clock.now)
        } catch BundleError.nothingToRollBackTo {
            throw ApiFailure(status: .conflict, code: "nothing_to_roll_back_to", message: "no earlier version was pinned")
        }
        try services.audit.record(actor: session.email, action: "bundle.rollback", target: version, at: services.clock.now)
        return try Json.response(try services.bundles.overview(now: services.clock.now))
    }

    private func install(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorWrite(request)
        try guards.limit("bundle-install", per: context, max: WorkloadRoutes.actionsPerMinute, seconds: 60)
        guard let machine = context.parameters.get("id"), Ids.isValid(machine) else { throw ApiFailure.notFound }
        let target = try InstallTarget(body: try await guards.body(request)).workload
        let command = try await services.workloads.installBundle(actor: session.email, machine: machine, workload: target)
        return try Json.response(["command": command], status: .accepted)
    }

    /// A link that opens the chat of one machine or workload. The access key rides after the #, so it is never sent to any server.
    private func chatLink(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorSession(request)
        let query = request.uri.queryParameters
        guard let machine = query.get("machine"), Ids.isValid(machine) else { throw ApiFailure.notFound }
        let workload = query.get("workload")
        guard workload == nil || Ids.isValid(workload!) else { throw ApiFailure.notFound }
        let target = workload.map { "\(machine)/\($0)" } ?? machine
        guard let stored = try services.chatAccess.get(target: target), let host = try chatHost(machine, workload), IPv4.isLoopbackOrPrivate(host) else { throw ApiFailure.notFound }
        let key = try services.secrets.open(stored.sealedKey)
        try services.audit.record(actor: session.email, action: "chat.link", target: target, at: services.clock.now)
        return try Json.response(["url": "http://\(host):\(stored.port)/#k=\(key)"])
    }

    private func chatHost(_ machine: String, _ workload: String?) throws -> String? {
        let summary: MachineSummary
        do { summary = try services.machines.get(id: machine, now: services.clock.now) } catch MachineError.notFound { throw ApiFailure.notFound }
        guard let workload else { return summary.ip }
        return summary.workloads.first { $0.id == workload }?.address
    }

    /// The Agent fetches the bundle it was told to install. Only with its machine token, and only files in the registry.
    private func download(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.machine(request, context: context)
        try services.bundles.rescan(now: services.clock.now)
        guard let version = context.parameters.get("version"), version.wholeMatch(of: Self.versionPattern) != nil,
              let platform = context.parameters.get("platform"), platform.wholeMatch(of: Self.platformPattern) != nil,
              let bundle = try services.bundles.find(version: version, platform: platform), let data = FileManager.default.contents(atPath: bundle.path) else { throw ApiFailure.notFound }
        var headers = HTTPFields()
        headers[.contentType] = "application/gzip"
        headers[HTTPField.Name("X-Bundle-Sha256")!] = bundle.sha256
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}

private struct PinRequest {
    let version: String

    init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["version"])
        let text = try object.string("version", maxLength: 16, minLength: 5)
        guard Ids.isSemver(text) else { throw InputError("version must look like 1.2.3") }
        version = text
    }
}

private struct InstallTarget {
    let workload: String?

    init(body: Data) throws {
        let object = try StrictObject(data: body.isEmpty ? Data("{}".utf8) : body, allowed: ["workload"])
        workload = object.has("workload") ? try object.id("workload") : nil
    }
}
