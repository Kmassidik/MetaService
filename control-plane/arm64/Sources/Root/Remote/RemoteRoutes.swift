import Foundation
import Hummingbird
import MSCore
import RootCore

/// Connect, as the panel calls it: the host key first, then the login that reads what the computer is, and the parent's public key.
struct RemoteRoutes {
    let services: Services
    let guards: Guards

    static let probesPerMinute = 10
    static let verifiesPerMinute = 6
    static let fixesPerMinute = 3

    func register(on group: RouterGroup<RootContext>) {
        group.post("/api/remote/probe", use: probe)
        group.post("/api/remote/verify", use: verify)
        group.post("/api/remote/fix", use: fix)
        group.get("/api/remote/key", use: key)
    }

    func probe(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("remote-probe", per: context, max: Self.probesPerMinute, seconds: 60)
        let body = try await parsed(request) { try ProbeRequest(body: $0) }
        return try await answer { try await services.remote.probe(body.target, actor: caller.name) }
    }

    func verify(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("remote-verify", per: context, max: Self.verifiesPerMinute, seconds: 60)
        let body = try await parsed(request) { try VerifyRequest(body: $0) }
        return try await answer { try await services.remote.verify(body, actor: caller.name) }
    }

    func fix(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("remote-fix", per: context, max: Self.fixesPerMinute, seconds: 60)
        let body = try await parsed(request) { try RemoteFixRequest(body: $0) }
        return try await answer { try await services.remoteFix.fix(body, actor: caller.name) }
    }

    func key(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try Json.response(PublicKey(publicKey: try services.remote.parentPublicKey()))
    }

    private func parsed<T>(_ request: Request, _ make: (Data) throws -> T) async throws -> T {
        do { return try make(try await guards.body(request)) } catch let error as InputError { throw ApiFailure.invalid(error.message) }
    }

    private func answer<T: Encodable>(_ work: () async throws -> T) async throws -> Response {
        do { return try Json.response(try await work()) } catch let failure as RemoteFailure { throw failure.api }
    }
}

private struct PublicKey: Encodable { let publicKey: String }
