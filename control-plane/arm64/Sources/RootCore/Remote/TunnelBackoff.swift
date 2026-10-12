import Foundation

public enum TunnelState: String, Encodable, Equatable, Sendable {
    case connecting, connected, disconnected
}

/// How long the parent waits before it tries a dropped tunnel again: quickly the first times, then less and less often, and never more than a minute, so a computer that is
/// switched off is not hammered with logins (which looks like an attack to the network).
public enum TunnelBackoff {
    public static let delays: [TimeInterval] = [1, 2, 5, 10, 30, 60]

    public static func delay(afterFailures failures: Int) -> TimeInterval {
        delays[min(max(failures, 1), delays.count) - 1]
    }
}
