import Hummingbird
import NIOCore

/// What every request carries: the caller's address, and a small body limit.
struct RootContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    let remoteIP: String

    static let maxBodyBytes = 64 * 1024
    var maxUploadSize: Int { Self.maxBodyBytes }

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        remoteIP = source.channel.remoteAddress?.ipAddress ?? "unknown"
    }
}
