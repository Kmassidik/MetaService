import Foundation

/// The cleaning every piece of text from a helper goes through before it is stored. A user name or an address comes from an attacker,
/// so it is only ever kept as short plain text; the panel shows it as plain text too.
public enum SecurityText {
    public static let maxUser = 64
    public static let maxAddress = 64
    public static let maxDetail = 160

    private static let ipv4 = #/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/#
    private static let ipv6 = #/^[0-9A-Fa-f:.]{2,}$/#
    private static let hostname = #/^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$/#
    private static let maxOctet = 255
    private static let minIPv6Colons = 2

    /// Control characters become spaces, runs of white space become one space, the ends are trimmed. Nil when nothing is left.
    public static func plain(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let spaced = raw.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) ? " " : Character(scalar)
        }
        let text = String(spaced).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// `plain`, cut to `limit` characters.
    public static func cut(_ raw: String?, limit: Int) -> String? {
        guard let text = plain(raw) else { return nil }
        let short = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? nil : short
    }

    public static func user(_ raw: String?) -> String? { cut(raw, limit: maxUser) }

    public static func detail(_ raw: String?) -> String? { cut(raw, limit: maxDetail) }

    /// An address must look like an IPv4 or IPv6 address or a host name and fit in 64 characters; anything else is dropped (nil), never cut, because half an address is a wrong address.
    public static func address(_ raw: String?) -> String? {
        guard let text = plain(raw), text.count <= maxAddress, looksLikeAddress(text) else { return nil }
        return text
    }

    private static func looksLikeAddress(_ text: String) -> Bool {
        if let octets = try? ipv4.wholeMatch(in: text) {
            return [octets.1, octets.2, octets.3, octets.4].allSatisfy { (Int($0) ?? Int.max) <= maxOctet }
        }
        if text.contains(":") { return isIPv6(text) }
        return (try? hostname.wholeMatch(in: text)) != nil
    }

    private static func isIPv6(_ text: String) -> Bool {
        (try? ipv6.wholeMatch(in: text)) != nil && text.filter { $0 == ":" }.count >= minIPv6Colons
    }
}
