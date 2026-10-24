import Foundation
import RootCore

/// One forwarded request, in plain values so the service needs no HTTP types: where it goes (the machine and the sandbox's
/// port), and what the caller sent (method, path, query, headers, body).
struct SandboxPortCall {
    let machine: String
    let sandbox: String
    let port: Int
    let method: String
    let path: String
    let query: String?
    /// The caller's own headers, as they arrived. The forwarder drops the ones that belong to this hop.
    let headers: [(name: String, value: String)]
    let body: Data
}

/// What the program inside answered: status, headers and body, passed on as they came.
struct SandboxPortReply {
    let status: Int
    let headers: [(name: String, value: String)]
    let body: Data
}

enum SandboxPortError: Error, Equatable {
    /// The machine could not be reached, or its answer was too big to pass on.
    case unreachable
}

/// The way one request reaches a sandbox's port. A protocol so the service can be driven without a machine in tests.
protocol SandboxPortForwarding: Sendable {
    func forward(_ call: SandboxPortCall) async throws -> SandboxPortReply
}

/// The parent's end of the helper's port route, over the same tunnel as every other parent→helper call.
///
/// The command token travels in `X-MetaService-Token` (`sandbox/helper.yaml`), never in `Authorization`, so the caller's own
/// `Authorization` header reaches the program inside untouched. The reply is buffered: streaming and WebSocket upgrades are a
/// later slice, which is why the size is capped and the timeout is finite.
struct AgentSandboxPortForwarder: SandboxPortForwarding {
    static let replySeconds: TimeInterval = 60
    /// The most either direction this forwarder carries today. A stream needs the streaming slice; a body larger than this is
    /// refused rather than quietly cut.
    static let maxBytes = 16 * 1024 * 1024
    static let commandTokenHeader = "X-MetaService-Token"
    /// Headers of this hop, or ones this call sets itself, so they are never copied from the caller.
    static let droppedRequestHeaders: Set<String> = [
        "host", "content-length", "connection", "keep-alive", "transfer-encoding", "upgrade", "proxy-connection", "te",
        "accept-encoding", "x-meta-service-token", "x-port-token",
    ]
    /// Hop headers on the way back. `content-encoding` goes too: the URL session has already unpacked the body it returns.
    static let droppedReplyHeaders: Set<String> = [
        "content-length", "connection", "keep-alive", "transfer-encoding", "upgrade", "proxy-connection", "content-encoding",
    ]
    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = replySeconds
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    let client: AgentClient

    func forward(_ call: SandboxPortCall) async throws -> SandboxPortReply {
        let path = PortForward.path(sandbox: call.sandbox, port: call.port, path: call.path, query: call.query)
        guard let (url, token) = try? client.target(machine: call.machine, scheme: "http", path: path) else {
            throw SandboxPortError.unreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.timeoutInterval = Self.replySeconds
        request.setValue(token, forHTTPHeaderField: Self.commandTokenHeader)
        for header in call.headers where !Self.droppedRequestHeaders.contains(header.name.lowercased()) {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if !call.body.isEmpty { request.httpBody = call.body }
        guard let (data, response) = try? await Self.session.data(for: request), let http = response as? HTTPURLResponse,
              data.count <= Self.maxBytes else {
            throw SandboxPortError.unreachable
        }
        let headers = http.allHeaderFields.compactMap { name, value -> (name: String, value: String)? in
            guard let name = name as? String, !Self.droppedReplyHeaders.contains(name.lowercased()) else { return nil }
            return (name: name, value: String(describing: value))
        }
        return SandboxPortReply(status: http.statusCode, headers: headers, body: data)
    }

    /// A redirect from a machine is never followed: it would leave the tunnel for an address the caller chose.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
