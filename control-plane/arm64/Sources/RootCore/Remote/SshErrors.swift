import Foundation

public enum SshErrorKind: Equatable, Sendable {
    case loginRefused, hostKeyChanged, unreachable, closed, other
}

/// What ssh's own words (its exit status and error text) mean. ssh says nothing at all when a server just drops the connection, which is what OpenSSH does to an address
/// after failed logins (its own protection against password guessing), so an empty answer with status 255 is "closed".
public enum SshErrors {
    private static let unreachableWords = ["connection refused", "no route to host", "timed out", "network is unreachable", "could not resolve", "operation timed out"]
    private static let closedWords = ["connection closed", "connection reset", "kex_exchange_identification", "broken pipe"]

    /// True when the server's refusal lists only public keys, as in `Permission denied (publickey).`: it takes no passwords over SSH at all, so no password can ever work.
    public static func offersOnlyKeys(_ errors: String) -> Bool {
        let text = errors.lowercased()
        guard let open = text.range(of: "permission denied ("), let close = text[open.upperBound...].firstIndex(of: ")") else { return false }
        let methods = text[open.upperBound..<close]
        return methods.contains("publickey") && !methods.contains("password") && !methods.contains("keyboard-interactive")
    }

    public static func classify(status: Int32, errors: String) -> SshErrorKind {
        let text = errors.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("permission denied") { return .loginRefused }
        if text.contains("host key verification failed") || text.contains("identification has changed") { return .hostKeyChanged }
        if unreachableWords.contains(where: text.contains) { return .unreachable }
        if closedWords.contains(where: text.contains) || (text.isEmpty && status == 255) { return .closed }
        return .other
    }
}
