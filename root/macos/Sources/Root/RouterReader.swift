import Foundation
import RootCore

enum RouterFailure: Error {
    case notConfigured
    case unreachable
    case refused(Int)
    case badReply
}

/// Anything that can list the devices a router knows about.
protocol RouterReader: Sendable {
    func entries() async throws -> [RouterEntry]
}

enum RouterReaders {
    /// https/http means the REST API (RouterOS 7); api and api-ssl mean the binary API (RouterOS 6 and later).
    static func make(config: RootConfig) -> RouterReader? {
        guard let text = config.routerURL, let scheme = URL(string: text)?.scheme else { return nil }
        return ["http", "https"].contains(scheme) ? RouterOSClient(config: config) : RouterOSApiClient(config: config)
    }
}
