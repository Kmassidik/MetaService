import Foundation

/// How a simulated install of a missing app goes (switched by tests). The simulated engine answers with the same lines the real script prints,
/// so the parser and the error mapping run the same way.
public enum SimulatedAppInstall: Equatable, Sendable {
    case works
    /// Waits this many seconds, then works.
    case delay(TimeInterval)
    case fails(AppScriptFailure)
    /// Prints nothing the helper can read.
    case garbage
    /// The run itself breaks (the VM stops answering, the time runs out).
    case breaks

    /// What the pretend vendor installer prints as its version, and the SHA-256 of the pretend installer file.
    public static let version = "2026.9.4"
    public static let sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    /// What the script prints for a finished run: the pretend installer's own line, the marker, and the result lines.
    static func output(_ app: AppKind, installed: Bool) -> String {
        let hash = installed ? "sha256=\(sha256)\n" : ""
        return "\(AppInstallScripts.resultMarker)\napp=\(app.rawValue)\ninstalled=\(installed)\nversion=\(version)\n\(hash)"
    }

    static func failureOutput(_ app: AppKind, _ failure: AppScriptFailure) -> String {
        "simulated installer output\n\(AppInstallScripts.resultMarker)\napp=\(app.rawValue)\ninstalled=false\nfailure=\(failure.rawValue)\n"
    }
}
