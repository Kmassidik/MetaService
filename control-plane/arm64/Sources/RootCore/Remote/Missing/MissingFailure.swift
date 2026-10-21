import Foundation

/// Why "Install it for me" did not finish, in words the person can act on. None of these texts holds the password.
public enum MissingFailure: Error, Equatable {
    case wrongPassword, notAllowed, needsPassword, needsTerminal, noSudo
    /// The install itself stopped; the text is what the script said (already without the password).
    case stopped(String)
    case unknown

    /// A short fixed name for the audit log. Never the text of an error, which came from the other computer.
    public var auditName: String {
        switch self {
        case .wrongPassword: return "wrong_password"
        case .notAllowed: return "not_allowed"
        case .needsPassword: return "needs_password"
        case .needsTerminal: return "needs_terminal"
        case .noSudo: return "no_sudo"
        case .stopped, .unknown: return "install_failed"
        }
    }

    public var message: String {
        switch self {
        case .wrongPassword: return "sudo did not accept that password. Check it and try again."
        case .notAllowed: return "that user is not allowed to use sudo on that computer, so MetaService cannot install anything there."
        case .needsPassword: return "that computer asks for a password for sudo. Type it in the password field."
        case .needsTerminal: return "sudo on that computer only works from a terminal window (requiretty), so it cannot be used from here."
        case .noSudo: return "sudo is not installed on that computer."
        case .stopped(let text): return text
        case .unknown: return "the install stopped and that computer did not say why."
        }
    }
}

/// Reads what came back from the one sudo command: success, or the reason in words. Sudo's own refusals are told apart from the script's.
public enum MissingOutcome {
    private static let longestText = 400
    private static let wrongPasswordWords = ["incorrect password", "try again", "no password was provided", "authentication failed", "authentication failure"]
    private static let notAllowedWords = ["is not in the sudoers", "may not run sudo", "not allowed to execute", "not allowed to run sudo", "is not allowed to"]
    private static let terminalWords = ["no tty present", "a terminal is required", "must have a tty"]

    public static func read(status: Int32, output: String, errors: String, password: SudoPassword) -> MissingFailure? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        if lines.contains(InstallMissingScripts.doneMarker) && status == 0 { return nil }
        guard lines.contains(InstallMissingScripts.okMarker) else { return sudoFailure(errors) }
        return .stopped(password.redacted(scriptMessage(lines)))
    }

    private static func sudoFailure(_ errors: String) -> MissingFailure {
        let text = errors.lowercased()
        if text.contains("sudo: a password is required") || text.contains("password is required") { return .needsPassword }
        if text.contains("sudo: command not found") || text.contains("sudo: not found") { return .noSudo }
        if terminalWords.contains(where: text.contains) { return .needsTerminal }
        if notAllowedWords.contains(where: text.contains) { return .notAllowed }
        if wrongPasswordWords.contains(where: text.contains) { return .wrongPassword }
        return .unknown
    }

    private static func scriptMessage(_ lines: [String]) -> String {
        let marker = InstallMissingScripts.errorMarker, detail = InstallMissingScripts.detailMarker
        guard let first = lines.first(where: { $0.hasPrefix(marker) }) else { return MissingFailure.unknown.message }
        let reason = first.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        let more = lines.filter { $0.hasPrefix(detail) }.map { $0.dropFirst(detail.count).trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return String((more.isEmpty ? reason : "\(reason) (\(more))").prefix(longestText))
    }
}
