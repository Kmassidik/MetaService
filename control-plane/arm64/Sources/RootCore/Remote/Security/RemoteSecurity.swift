import Foundation

/// What the security look found about a computer before anything is installed there. Every field is nil when it could not be told: "unknown" is never turned into
/// a yes, a no or a zero. It is shown in the Verify reply as `security`, with an explicit null for each unknown field.
public struct RemoteSecurity: Equatable, Sendable, Encodable {
    public enum BanTool: String, Sendable, Equatable {
        case running
        case notRunning = "not_running"
        case notAvailable = "not_available"
    }

    /// True when SSH accepts a password.
    public var passwordLogin: Bool?
    public var banTool: BanTool?
    public var firewall: Bool?
    public var autoUpdates: Bool?
    public var pendingUpdates: Int?
    /// True when the login user has a key in authorized_keys, so turning password login off cannot lock that user out.
    public var hasKeyLogin: Bool?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case passwordLogin = "password_login", banTool = "ban_tool", firewall, autoUpdates = "auto_updates", pendingUpdates = "pending_updates", hasKeyLogin = "has_key_login"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(passwordLogin, forKey: .passwordLogin)
        try container.encode(banTool?.rawValue, forKey: .banTool)
        try container.encode(firewall, forKey: .firewall)
        try container.encode(autoUpdates, forKey: .autoUpdates)
        try container.encode(pendingUpdates, forKey: .pendingUpdates)
        try container.encode(hasKeyLogin, forKey: .hasKeyLogin)
    }
}

/// Reads the answer of `SecurityVerifyScript`. The text comes from another computer, so it is untrusted: only known keys are read, a value must be one of a
/// fixed set (or a bounded number), a line with anything but plain printable characters is ignored, and the first line for a key wins. Nothing here is ever shown as text.
public enum RemoteSecurityParse {
    public static let longestLine = 64
    public static let mostLines = 64
    public static let mostPending = 100_000

    public static func parse(_ text: String) -> RemoteSecurity {
        var security = RemoteSecurity()
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline).prefix(mostLines) {
            guard line.count <= longestLine, line.unicodeScalars.allSatisfy(isPlain), let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            guard seen.insert(key).inserted else { continue }
            apply(key: key, value: String(line[line.index(after: equals)...]), to: &security)
        }
        return security
    }

    private static func isPlain(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 32 && scalar.value < 127 }

    private static func apply(key: String, value: String, to security: inout RemoteSecurity) {
        switch key {
        case "password_login": security.passwordLogin = flag(value)
        case "ban_tool": security.banTool = RemoteSecurity.BanTool(rawValue: value)
        case "firewall": security.firewall = flag(value)
        case "auto_updates": security.autoUpdates = flag(value)
        case "has_key_login": security.hasKeyLogin = flag(value)
        case "pending_updates": security.pendingUpdates = count(value)
        default: break
        }
    }

    private static func flag(_ value: String) -> Bool? {
        switch value {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    /// Digits only, so "-1", "1e3", "0x10" and "3 " are all unknown.
    private static func count(_ value: String) -> Int? {
        guard !value.isEmpty, value.count <= 6, value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber), let number = Int(value), number <= mostPending else { return nil }
        return number
    }
}
