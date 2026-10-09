import Foundation

public enum Origin {
    /// The exact origin (scheme://host[:port]) of a URL string, lowercased; nil if it has none.
    public static func of(_ url: String) -> String? {
        guard let parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        let port = parts.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// True only when the Origin header is present and equals the expected origin exactly.
    public static func matches(header: String?, expected: String) -> Bool {
        guard let header, let given = of(header), let wanted = of(expected) else { return false }
        return given == wanted && header.lowercased().hasPrefix(given) && header.count == given.count
    }
}
