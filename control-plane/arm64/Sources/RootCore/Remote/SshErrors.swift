import Foundation

public enum SshErrorKind: Equatable, Sendable {
    case loginRefused, hostKeyChanged, unreachable, closed, other
}

/// What ssh's own words (its exit status and error text) mean. ssh says nothing at all when a server just drops the connection, which is what OpenSSH does to an address
/// after failed logins (its own protection against password guessing), so an empty answer with status 255 is "closed".
public enum SshErrors {
    private static let unreachableWords = ["connection refused", "no route to host", "timed out", "network is unreachable", "could not resolve", "operation timed out"]
    private static let closedWords = ["connection closed", "connection reset", "kex_exchange_identification", "broken pipe"]

    /// The logins a server says it accepts, from its refusal: `Permission denied (publickey,password).` gives ["publickey", "password"]. Nil when ssh did not say.
    public static func methods(in errors: String) -> [String]? {
        let text = errors.lowercased()
        guard let open = text.range(of: "permission denied ("), let close = text[open.upperBound...].firstIndex(of: ")") else { return nil }
        return text[open.upperBound..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// True when the server's refusal lists only public keys: it takes no passwords over SSH at all, so no password can ever work.
    public static func offersOnlyKeys(_ errors: String) -> Bool {
        guard let methods = methods(in: errors) else { return false }
        return methods.contains("publickey") && !methods.contains("password") && !methods.contains("keyboard-interactive")
    }

    /// Windows' OpenSSH runs the check with cmd.exe or PowerShell, which both say that `sh` is "not recognized". No Mac or Linux login says that.
    public static func looksLikeWindows(_ errors: String) -> Bool {
        errors.lowercased().contains("is not recognized as")
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
