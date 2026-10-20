import Hummingbird
import MSCore
import NIOCore

/// What every request carries: the caller's address, and a small body limit.
struct RootContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    var remoteIP: String

    static let maxBodyBytes = 64 * 1024
    var maxUploadSize: Int { Self.maxBodyBytes }

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        remoteIP = source.channel.remoteAddress?.ipAddress ?? "unknown"
    }
}

extension RootContext {
    /// The machine id in the address of a /api/machines/{id}/... route. Anything that is not a valid id is "no such thing".
    func machineId() throws -> String {
        guard let id = parameters.get("id"), Ids.isValid(id) else { throw ApiFailure.notFound }
        return id
    }
}
