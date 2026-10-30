import Foundation
import RootCore

enum JoinShareFailure: Error {
    case notConfigured
    case unreachable
}

/// What the hub answered: its status and its JSON body, unchanged.
struct JoinShareReply {
    let status: Int
    let body: Data
}

/// The parent's only way to the join-share hub's admin listener: one fixed address from the settings, the key read from its file at every call
/// and sent only as the X-Admin-Key header, no redirects, a short timeout. The key is never logged, never put in an error and never returned.
struct JoinShareHub: Sendable {
    let config: RootConfig

    static let keyHeader = "X-Admin-Key"
    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = JoinShareRules.timeoutSeconds
        options.timeoutIntervalForResource = JoinShareRules.timeoutSeconds
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    var isConfigured: Bool { config.joinShareAdminURL != nil }

    /// Calls the hub. An unreadable or empty key file, a refused connection, a timeout and a reply that is not usable are all "unreachable":
    /// the browser is told nothing more.
    func send(method: String, path: String, body: Data? = nil) async throws -> JoinShareReply {
        guard let base = config.joinShareAdminURL, let keyFile = config.joinShareAdminKeyFile else { throw JoinShareFailure.notConfigured }
        guard let text = try? String(contentsOfFile: keyFile, encoding: .utf8), let key = JoinShareRules.adminKey(fileText: text),
              let url = URL(string: base + path) else { throw JoinShareFailure.unreachable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = JoinShareRules.timeoutSeconds
        request.setValue(key, forHTTPHeaderField: Self.keyHeader)
        if let body, !body.isEmpty {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        guard let (data, response) = try? await Self.session.data(for: request), let http = response as? HTTPURLResponse,
              JoinShareRules.isPassableReply(data, key: key) else { throw JoinShareFailure.unreachable }
        return JoinShareReply(status: http.statusCode, body: data)
    }

    /// True when the hub answers its supported table with 200.
    func isReachable() async -> Bool {
        guard let reply = try? await send(method: "GET", path: "/admin/supported") else { return false }
        return reply.status == 200
    }

    /// A redirect from the hub is never followed: it would take the key to an address the hub chose.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
