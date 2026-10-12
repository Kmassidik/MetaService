import Foundation

public enum RemoteTargetError: Error, Equatable {
    case badHost, badPort, badUser, outsideNetwork
}

extension IPv4 {
    /// A private (RFC 1918) address, not loopback: the only kind of computer the operator may connect to.
    public static func isPrivate(_ text: String) -> Bool { isLoopbackOrPrivate(text) && !isLoopback(text) }

    public static func isLoopback(_ text: String) -> Bool { (Subnet.address(text) ?? 0) >> 24 == 127 }
}

/// The computer the operator wants to connect to: where it is and who to log in as. Checked before anything touches the network.
/// A host or user that starts with "-" is refused, so it can never be read as an option of the ssh program.
public struct RemoteTarget: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let user: String

    public static let defaultPort = 22
    private static let hostName = try! NSRegularExpression(pattern: "^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")
    private static let userName = try! NSRegularExpression(pattern: "^[A-Za-z_][A-Za-z0-9_.-]{0,31}$")

    public init(host: String, port: Int? = nil, user: String) throws {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard Self.matches(Self.hostName, trimmed) else { throw RemoteTargetError.badHost }
        guard Self.matches(Self.userName, user) else { throw RemoteTargetError.badUser }
        let chosen = port ?? Self.defaultPort
        guard (1...65535).contains(chosen) else { throw RemoteTargetError.badPort }
        self.host = trimmed.lowercased()
        self.port = chosen
        self.user = user
    }

    public var isAddress: Bool { IPv4.isValid(host) }

    /// Whether this address may be a target: a private address, and loopback only when the operator turned that on (the tests and demos do).
    public static func allowed(address: String, allowLoopback: Bool, subnet: Subnet?) -> Bool {
        if IPv4.isLoopback(address) { return allowLoopback }
        guard IPv4.isPrivate(address) else { return false }
        return subnet?.contains(address) ?? true
    }

    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
