import Foundation

/// Who the visitor really is, for the lockout and the audit trail. Behind the local Cloudflare connector every connection comes from this machine,
/// so without this every visitor would share one address: one attacker could lock the real operator out.
public enum ClientAddress {
    public static let header = "CF-Connecting-IP"

    /// The address the connector reports, but only when the connection itself comes from this machine and the site is public. Anything else, or
    /// anything that is not an address, keeps the connection's own address, so a visitor can never choose the address it is counted under.
    public static func resolve(peer: String, forwarded: String?, trustForwarded: Bool) -> String {
        guard trustForwarded, OperatorGate.isLoopback(peer), let forwarded, isAddress(forwarded) else { return peer }
        return forwarded
    }

    static func isAddress(_ text: String) -> Bool { IPv4.isValid(text) || isIPv6(text) }

    private static let maxIPv6Groups = 8

    /// A real IPv6 address: groups of 1 to 4 hex digits, one "::" at most standing for the zeros, and an optional dotted IPv4 tail.
    /// The text is used as a counting key and printed in the audit log, so junk must not pass.
    static func isIPv6(_ text: String) -> Bool {
        guard text.count <= 45, text.contains(":"), text.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return false }
        let sides = text.components(separatedBy: "::")
        guard sides.count <= 2 else { return false }
        let groups = sides.flatMap { $0.isEmpty ? [String]() : $0.components(separatedBy: ":") }
        guard let count = groupCount(groups) else { return false }
        return sides.count == 2 ? count < maxIPv6Groups : count == maxIPv6Groups
    }

    /// How many 16-bit groups the pieces stand for, or nil when one is not valid. A dotted IPv4 tail counts for two.
    private static func groupCount(_ groups: [String]) -> Int? {
        var count = 0
        for (index, group) in groups.enumerated() {
            let isTail = index == groups.count - 1 && group.contains(".")
            guard isTail ? IPv4.isValid(group) : (1...4).contains(group.count) && group.allSatisfy({ $0.isHexDigit }) else { return nil }
            count += isTail ? 2 : 1
        }
        return count
    }
}
