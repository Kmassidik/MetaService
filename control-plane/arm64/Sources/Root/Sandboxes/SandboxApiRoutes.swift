import Foundation
import Hummingbird
import HTTPTypes
import RootCore
import RootStore

/// The public sandbox API (`sandbox/api.yaml`). A separate router group with its own guard, mounted where the sandbox API's
/// own name reaches this process (5c puts that name on the Cloudflare tunnel). It shares no cookie, no CSRF token and no Host
/// check with the operator routes above.
///
/// The paths are E2B's, exactly as the SDKs call them: create and list under `/v2/sandboxes`, one sandbox and its timeout
/// under `/sandboxes/{sandboxID}`, and connect under `/v2/sandboxes/{sandboxID}/connect`. That mix is E2B's, not a typo.
struct SandboxApiRoutes {
    let services: Services
    let gate: SandboxApiGuard
    let helper: SandboxHelperCalling

    func register(on group: RouterGroup<RootContext>) {
        group.post("/v2/sandboxes", use: create)
        group.get("/v2/sandboxes", use: list)
        group.get("/sandboxes/{sandboxID}", use: detail)
        group.delete("/sandboxes/{sandboxID}", use: remove)
        group.post("/sandboxes/{sandboxID}/timeout", use: setTimeout)
        group.post("/sandboxes/{sandboxID}/pause", use: pause)
        group.get("/sandboxes/{sandboxID}/metrics", use: metrics)
        group.post("/v2/sandboxes/{sandboxID}/connect", use: connect)
    }

    private var service: SandboxApiService { SandboxApiService(services: services, helper: helper) }

    // MARK: routes

    private func create(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            try gate.limitCreates(for: key)
            let spec = try SandboxApiCreateBody.parse(try await body(request))
            let answer = try await service.create(key: key, spec: spec)
            return try SandboxApiJson.response(answer.sandbox, status: .created)
        }
    }

    private func list(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            let query = try SandboxApiListQuery.parse(parameters(of: request))
            return try SandboxApiJson.response(try service.list(team: key.team, query: query))
        }
    }

    private func detail(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            return try SandboxApiJson.response(try service.detail(team: key.team, id: try sandboxID(context)))
        }
    }

    private func remove(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            try gate.limitChanges(for: key)
            try await service.remove(team: key.team, id: try sandboxID(context), key: key)
            return Response(status: .noContent)
        }
    }

    private func setTimeout(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            try gate.limitChanges(for: key)
            let body = try SandboxApiTimeoutBody.parse(try await body(request))
            try await service.setTimeout(team: key.team, id: try sandboxID(context), body: body, key: key)
            return Response(status: .noContent)
        }
    }

    /// Save and stop the sandbox. Its files and running programs carry on after a connect.
    private func pause(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            try gate.limitChanges(for: key)
            try await service.pause(team: key.team, id: try sandboxID(context), key: key)
            return Response(status: .noContent)
        }
    }

    /// The readings the helper took, forwarded unchanged; `start` and `end` are Unix seconds.
    private func metrics(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            let readings = try await service.metrics(team: key.team, id: try sandboxID(context),
                                                     from: try queryNumber("start", in: request), until: try queryNumber("end", in: request))
            return try SandboxApiJson.raw(readings)
        }
    }

    private func connect(_ request: Request, context: RootContext) async -> Response {
        await attempt(context) {
            let key = try gate.caller(request, context: context)
            try gate.limitChanges(for: key)
            let body = try SandboxApiConnectBody.parse(try await body(request))
            let answer = try await service.connect(team: key.team, id: try sandboxID(context), body: body, key: key)
            return try SandboxApiJson.response(answer.sandbox, status: answer.resumed ? .created : .ok)
        }
    }

    // MARK: pieces

    /// A whole, non-negative number from the query string, or nil when the parameter is absent. Anything else is the API's 400.
    private func queryNumber(_ name: String, in request: Request) throws -> Int? {
        guard let query = request.uri.query else { return nil }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.first == Substring(name) else { continue }
            guard parts.count == 2, let value = Int(parts[1]), value >= 0 else {
                throw SandboxApiFailure(status: 400, message: "\(name) must be whole seconds.")
            }
            return value
        }
        return nil
    }

    /// A sandbox id that is not even shaped like one is "no such sandbox", the same as an unknown one.
    private func sandboxID(_ context: RootContext) throws -> String {
        guard let id = context.parameters.get("sandboxID"), SandboxIdentity.isValid(id) else { throw SandboxApiFailure.noSuchSandbox() }
        return id
    }

    /// The body, up to the same small limit as the panel: a create is a template name, a timeout and some variables.
    private func body(_ request: Request) async throws -> Data {
        if let declared = request.headers[.contentLength].flatMap({ Int($0) }), declared > RootContext.maxBodyBytes {
            throw SandboxApiFailure(status: 413, message: "The body is too large.", errorCode: "too_large")
        }
        let buffer = try await request.body.collect(upTo: RootContext.maxBodyBytes)
        return Data(buffer.readableBytesView)
    }

    /// Every failure of this API becomes its own `{ code, message, error_code }`, never the panel's shape and never a 500
    /// with the inside in it.
    private func attempt(_ context: RootContext, _ work: () async throws -> Response) async -> Response {
        do {
            return try await work()
        } catch let failure as SandboxApiFailure {
            return SandboxApiJson.failure(failure)
        } catch let error as HTTPError {
            return SandboxApiJson.failure(SandboxApiFailure(status: error.status.code, message: "The request was refused.", errorCode: "refused"))
        } catch {
            context.logger.error("sandbox api: unexpected \(type(of: error))")
            return SandboxApiJson.failure(SandboxApiFailure(status: 500, message: "Something went wrong on our side.", errorCode: "internal"))
        }
    }

    /// The query as plain strings, whatever the router's own container is.
    private func parameters(of request: Request) -> [String: String] {
        var values: [String: String] = [:]
        for (name, value) in request.uri.queryParameters { values[String(name)] = String(value) }
        return values
    }
}
