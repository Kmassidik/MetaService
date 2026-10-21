import Hummingbird
import HummingbirdWebSocket
import NIOConcurrencyHelpers
import RootCore

/// What the checks before the upgrade learned: which console, for which operator. The upgrade handler reads it, so a ticket is spent only once.
final class ConsoleClaim: Sendable {
    struct Value: Sendable {
        let key: ConsoleKey
        let operatorName: String
    }

    private let value = NIOLockedValueBox<Value?>(nil)

    func set(_ claimed: Value) { value.withLockedValue { $0 = claimed } }
    func get() -> Value? { value.withLockedValue { $0 } }
}

/// The request context of the console socket router.
struct TerminalContext: RequestContext, WebSocketRequestContext {
    var coreContext: CoreRequestContextStorage
    let webSocket: WebSocketHandlerReference<Self>
    let claim = ConsoleClaim()

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
        webSocket = .init()
    }
}
