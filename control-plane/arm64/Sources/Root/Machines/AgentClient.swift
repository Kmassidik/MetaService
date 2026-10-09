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

    private static let maxReplyBytes = 256 * 1024
    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    func call(machine: String, method: String, path: String, body: [String: Any]? = nil, commandId: String? = nil) async throws -> AgentReply {
        guard let endpoint = try machines.endpoint(id: machine) else { throw AgentCallFailure.neverHeardFrom }
        guard IPv4.isLoopbackOrPrivate(endpoint.ip), let url = URL(string: "http://\(endpoint.ip):\(endpoint.port)\(path)") else { throw AgentCallFailure.notAllowedAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try secrets.open(endpoint.sealedCommandToken))", forHTTPHeaderField: "Authorization")
        if let commandId { request.setValue(commandId, forHTTPHeaderField: "X-Command-Id") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        guard let (data, response) = try? await Self.session.data(for: request), let http = response as? HTTPURLResponse, data.count <= Self.maxReplyBytes else { throw AgentCallFailure.unreachable }
        return AgentReply(status: http.statusCode, json: (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
