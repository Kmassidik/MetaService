import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore

/// The panel's Share a PC page talks to the join-share hub through these routes. The browser never sees the hub's admin key: the parent adds it.
/// Every route needs the operator's session; writes also need the exact Origin and the CSRF header. Method and path are matched against an allow-list
/// (`JoinShareRules.match`), so the hub is never given a path the browser chose, and the hub's status and JSON body are passed on unchanged.
struct JoinShareRoutes {
    let services: Services
    let guards: Guards

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/join-share/status", use: status)
        group.get("/api/join-share/supported", use: read)
        group.get("/api/join-share/pending", use: read)
        group.get("/api/join-share/peers", use: read)
        group.post("/api/join-share/links", use: write)
        group.post("/api/join-share/pending/{id}/approve", use: write)
        group.post("/api/join-share/pending/{id}/refuse", use: write)
        group.delete("/api/join-share/peers/{name}", use: write)
    }

    private func status(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let hub = services.joinShare
        let reachable = hub.isConfigured ? await hub.isReachable() : false
        return try Json.response(JoinShareStatus(configured: hub.isConfigured, reachable: reachable))
    }

    private func read(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try await forward(request, caller: nil)
    }

    private func write(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        return try await forward(request, caller: caller)
    }

    /// One allow-listed call to the hub. A write is audited with the operator and the target once the hub has answered (the status in the detail), never with the body.
    private func forward(_ request: Request, caller: OperatorCaller?) async throws -> Response {
        guard case .hub(let call)? = JoinShareRules.match(method: request.method.rawValue, path: request.uri.path) else { throw ApiFailure.notFound }
        let hub = services.joinShare
        guard hub.isConfigured else { return Self.refusal(.notFound, "not_configured") }
        let body = call.method == "POST" ? try await readBody(request) : nil
        let reply: JoinShareReply
        do {
            reply = try await hub.send(method: call.method, path: call.hubPath, body: body)
        } catch {
            return Self.refusal(.badGateway, "hub_unreachable")
        }
        if let caller, let action = call.auditAction {
            let target = call.auditTarget ?? JoinShareRules.linkTarget(body: body ?? Data())
            try services.audit.record(actor: caller.name, action: action, target: target, detail: ["status": String(reply.status)], at: services.clock.now)
        }
        return Self.passThrough(reply)
    }

    /// At most 16 KiB, and one JSON object (or nothing): that is all the hub is ever sent.
    private func readBody(_ request: Request) async throws -> Data {
        if let declared = request.headers[.contentLength].flatMap({ Int($0) }), declared > JoinShareRules.maxBodyBytes { throw HTTPError(.contentTooLarge) }
        let buffer = try await request.body.collect(upTo: JoinShareRules.maxBodyBytes)
        let body = Data(buffer.readableBytesView)
        guard JoinShareRules.isForwardableBody(body) else { throw ApiFailure.invalid("the body must be one JSON object") }
        return body
    }

    private static func passThrough(_ reply: JoinShareReply) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: HTTPResponse.Status(code: reply.status), headers: headers, body: .init(byteBuffer: ByteBuffer(data: reply.body)))
    }

    /// The two answers of the proxy itself, in the hub's own `{"error": "..."}` shape so the page reads every refusal the same way.
    private static func refusal(_ status: HTTPResponse.Status, _ code: String) -> Response {
        passThrough(JoinShareReply(status: Int(status.code), body: Data("{\"error\":\"\(code)\"}".utf8)))
    }
}

private struct JoinShareStatus: Encodable {
    let configured: Bool
    let reachable: Bool
}
