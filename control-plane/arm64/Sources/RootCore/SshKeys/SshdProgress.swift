import Foundation

/// Where setting up the SSH server inside a VM stands: nothing going on, an apply is running, or the last one failed.
public enum SshdPhase: String, Equatable {
    case idle, installing, failed
}

/// The stored progress of one VM's apply, and the rules that read it. `since` is when the phase began, in seconds since 1970.
/// Where it lives: `RootCore/SshKeys`. The store keeps the three values; this file decides what they mean at a given time.
public struct SshdProgress: Equatable {
    public let phase: SshdPhase
    /// A plain reason, only while `failed`.
    public let message: String?
    public let since: Int?

    public static let idle = SshdProgress(phase: .idle, message: nil, since: nil)

    public init(phase: SshdPhase, message: String?, since: Int?) {
        self.phase = phase
        self.message = message
        self.since = since
    }

    /// An install can take minutes, so an apply that began longer ago than this has died (for example with a restart of the parent).
    public static let installingTimeoutSeconds = 6 * 60
    /// A failed apply is not tried again by the heartbeat before this long has passed.
    public static let retryWaitSeconds = 60
    public static let interruptedMessage = "Setting up SSH did not finish. The parent may have restarted. Try again."
    public static let oldHelperMessage = "This machine's helper is too old to set up SSH inside the VM. Update the helper in Environment."
    public static let unclearFailureMessage = "Setting up SSH inside the VM failed. Try again."
    static let maxMessageCharacters = 300
    private static let firstPrintable: UInt32 = 0x20
    private static let delete: UInt32 = 0x7f

    /// What to show at `now`: an `installing` that is older than the limit is a failure with a plain message, never an endless wait.
    public func atTime(_ now: Int) -> SshdProgress {
        guard phase == .installing, let since, now - since >= Self.installingTimeoutSeconds else { return self }
        return SshdProgress(phase: .failed, message: Self.interruptedMessage, since: since + Self.installingTimeoutSeconds)
    }

    /// Whether the heartbeat may start an apply now. An apply that is running is left alone; a failed one waits its minute.
    public func mayStartFromHeartbeat(at now: Int) -> Bool {
        let current = atTime(now)
        switch current.phase {
        case .idle: return true
        case .installing: return false
        case .failed: return now - (current.since ?? 0) >= Self.retryWaitSeconds
        }
    }

    /// The helper's own words for a failure, as one plain line: control characters removed, cut at a limit. Anything empty becomes a generic sentence.
    public static func failureMessage(from helperText: String?) -> String {
        let printable = (helperText ?? "").unicodeScalars.filter { $0.value >= firstPrintable && $0.value != delete }
        let line = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? unclearFailureMessage : String(line.prefix(maxMessageCharacters))
    }
}
