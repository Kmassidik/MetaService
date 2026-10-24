import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore

/// The public port route: a request to `<label>.<domain>`, of any method and on any path, is forwarded to the sandbox's port
/// behind that label (see `sandbox/README.md`, "Addresses").
///
/// It is a middleware rather than a route on purpose. It has to see every method and every path, including the paths the
/// panel and the public API already answer (`/api/...`, `/v2/...`) and paths nothing answers: those are all the sandbox's
/// once the Host says it is a port host. A `Host` that is not a label host passes straight through to the routes as before,
/// so the panel is untouched.
///
/// The work is in `SandboxPortService`; this file only reads the request, renders refusals and copies the answer back.
struct SandboxPortRoutes: RouterMiddleware {
    let services: Services

    /// What the forwarder carries today, so a body it would refuse is refused here before it is read.
    static let maxBodyBytes = AgentSandboxPortForwarder.maxBytes
    static let tokenHeader = HTTPField.Name(PortToken.headerName)!

    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        guard PortHosts.label(inHost: request.head.authority, domain: services.config.sandboxDomain) != nil else {
            return try await next(request, context)
        }
        do {
            return try await forward(request, context: context)
        } catch let failure as SandboxApiFailure {
            return SandboxApiJson.failure(failure)
        } catch {
            context.logger.error("sandbox port: unexpected \(type(of: error))")
            return SandboxApiJson.failure(.portUnreachable)
        }
    }

    private func forward(_ request: Request, context: RootContext) async throws -> Response {
        let reply = try await service.forward(incoming(request, body: try await body(request, context: context)))
        return Response(status: .init(code: reply.status), headers: headers(of: reply), body: .init(byteBuffer: ByteBuffer(data: reply.body)))
    }

    private var service: SandboxPortService {
        SandboxPortService(services: services, forwarder: services.sandboxPortForwarder)
    }

    private func incoming(_ request: Request, body: Data) -> SandboxPortIncoming {
        let query = request.uri.query
        return SandboxPortIncoming(host: request.head.authority, method: request.method.rawValue, path: request.uri.path.isEmpty ? "/" : request.uri.path,
                                   query: query, token: PortToken.presented(query: query, header: request.headers[Self.tokenHeader]),
                                   headers: request.headers.map { (name: $0.name.canonicalName, value: $0.value) }, body: body)
    }

    /// The body, up to the forwarder's own cap. A larger one is refused rather than cut, because a cut body is a different
    /// request than the one the caller sent.
    private func body(_ request: Request, context: RootContext) async throws -> Data {
        if let declared = request.headers[.contentLength].flatMap({ Int($0) }), declared > Self.maxBodyBytes {
            throw SandboxApiFailure.portTooLarge
        }
        guard let buffer = try? await request.body.collect(upTo: Self.maxBodyBytes) else { throw SandboxApiFailure.portTooLarge }
        return Data(buffer.readableBytesView)
    }

    /// The answer's headers, minus anything that is not a valid HTTP field name (a machine may say something odd, and that is
    /// no reason to fail the request).
    private func headers(of reply: SandboxPortReply) -> HTTPFields {
        var fields = HTTPFields()
        for header in reply.headers {
            guard let name = HTTPField.Name(header.name) else { continue }
            fields.append(HTTPField(name: name, value: header.value))
        }
        return fields
    }
}
