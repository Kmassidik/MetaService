import Foundation
import MSCore
import RootCore
import RootStore

enum AgentCallFailure: Error {
    case neverHeardFrom
    case notAllowedAddress
    case unreachable
}

struct AgentReply {
    let status: Int
    let json: [String: Any]?
}

/// How the Root talks to an Agent. Only loopback and private addresses are ever called, with the machine's own command token.
struct AgentClient: Sendable {
    let machines: MachineStore
    let secrets: SecretBox
    let tunnels: TunnelPorts

    private static let maxReplyBytes = 256 * 1024
    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    func call(machine: String, method: String, path: String, body: [String: Any]? = nil, commandId: String? = nil) async throws -> AgentReply {
        let reply = try await send(machine: machine, method: method, path: path, body: body, commandId: commandId)
        return AgentReply(status: reply.status, json: (try? JSONSerialization.jsonObject(with: reply.data)) as? [String: Any])
    }

    private func send(machine: String, method: String, path: String, body: [String: Any]?, commandId: String?) async throws -> (status: Int, contentType: String?, data: Data) {
        guard let endpoint = try machines.endpoint(id: machine) else { throw AgentCallFailure.neverHeardFrom }
        let (host, port) = try Self.address(of: endpoint, through: tunnels.route(for: machine))
        guard IPv4.isLoopbackOrPrivate(host), let url = URL(string: "http://\(host):\(port)\(path)") else { throw AgentCallFailure.notAllowedAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try secrets.open(endpoint.sealedCommandToken))", forHTTPHeaderField: "Authorization")
        if let commandId { request.setValue(commandId, forHTTPHeaderField: "X-Command-Id") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await Self.session.data(for: request), let http = response as? HTTPURLResponse, data.count <= Self.maxReplyBytes else { throw AgentCallFailure.unreachable }
        return (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), data)
    }

    /// A machine with a tunnel is called on the tunnel's local port, and on nothing else; one without is called on the address it reported from.
    static func address(of endpoint: AgentEndpoint, through route: Int??) throws -> (String, Int) {
        switch route {
        case .none: return (endpoint.ip, endpoint.port)
        case .some(.none): throw AgentCallFailure.unreachable
        case .some(.some(let port)): return ("127.0.0.1", port)
        }
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
