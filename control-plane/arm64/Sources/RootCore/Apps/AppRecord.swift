import Foundation

/// Where setting up an app inside a VM stands. `none` means the app is wanted but nothing has started yet (for example the VM is stopped).
public enum AppPhase: String, Equatable {
    case none, installing, ready, failed
}

/// What the parent keeps about one VM's app, and the rules that read it. Times are seconds since 1970.
/// `updatedAt` is when the phase last changed, which starts the wait before the heartbeat tries a failed install again.
public struct AppRecord: Equatable {
    public let app: String
    public let phase: AppPhase
    public let message: String?
    public let version: String?
    public let installerSha256: String?
    public let logTail: [String]
    public let startedAt: Int?
    public let updatedAt: Int

    /// An install can take many minutes, so one that began longer ago than this has died (for example with a restart of the parent).
    public static let installingTimeoutSeconds = 30 * 60
    /// A failed install is not tried again by the heartbeat before this long has passed.
    public static let retryWaitSeconds = 60
    public static let interruptedMessage = "Setting up the app did not finish. The parent may have restarted. Try again."
    public static let unclearFailureMessage = "Setting up the app failed. Try again."

    public init(app: String, phase: AppPhase, message: String?, version: String?, installerSha256: String?, logTail: [String], startedAt: Int?, updatedAt: Int) {
        self.app = app
        self.phase = phase
        self.message = message
        self.version = version
        self.installerSha256 = installerSha256
        self.logTail = logTail
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    /// What to show at `now`: an `installing` that is older than the limit reads as a failure with a plain message, never an endless wait.
    public func atTime(_ now: Int) -> AppRecord {
        guard phase == .installing, let startedAt, now - startedAt >= Self.installingTimeoutSeconds else { return self }
        return AppRecord(app: app, phase: .failed, message: Self.interruptedMessage, version: version, installerSha256: installerSha256, logTail: logTail,
                         startedAt: startedAt, updatedAt: startedAt + Self.installingTimeoutSeconds)
    }

    /// Whether the heartbeat may start an install now: one that is wanted and not started, or a failed one after its wait. Running and finished ones are left alone.
    public func mayStartFromHeartbeat(at now: Int) -> Bool {
        let current = atTime(now)
        switch current.phase {
        case .none: return true
        case .installing, .ready: return false
        case .failed: return now - current.updatedAt >= Self.retryWaitSeconds
        }
    }
}
