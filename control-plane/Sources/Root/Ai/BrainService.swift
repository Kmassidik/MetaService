import Foundation
import RootCore

enum BrainFailure: Error {
    case notConfigured
    case upstream
}

/// The metered proxy's only way out: one fixed provider address, one key, one kind of request, no redirects.
struct BrainService: Sendable {
    let config: RootConfig

    private static let maxReplyBytes = 256 * 1024
    private static let requestSeconds: TimeInterval = 60
    private static let session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = requestSeconds
        options.httpCookieStorage = nil
        options.urlCache = nil
        return URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }()

    func ask(_ message: String, maxTokens: Int? = nil) async throws -> BrainAnswer {
        guard config.aiConfigured, let base = config.aiBaseURL, let key = config.aiApiKey, let model = config.aiModel,
              let url = BrainRules.completionsURL(base: base) else { throw BrainFailure.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try BrainRules.upstreamBody(message: message, model: model, maxTokens: min(maxTokens ?? config.aiMaxTokens, config.aiMaxTokens))
        guard let (data, response) = try? await Self.session.data(for: request), let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= Self.maxReplyBytes, let answer = BrainRules.parseReply(data) else { throw BrainFailure.upstream }
        return answer
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
