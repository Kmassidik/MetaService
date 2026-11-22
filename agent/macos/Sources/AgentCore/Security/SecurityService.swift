import Foundation

/// What `GET /v1/security/events` answers: the baseline of the machine. macOS logs no user or
/// address for SSH (see docs/security-model.md), so the agent reports no events; attempts are
/// counted where the OS can see them (Linux journalctl, and macOS VERBOSE sshd once rolled out).
public final class SecurityService {
    private let config: SshdConfigResolver
    private let files: MacFiles
    private let homeDirectory: String
    private let run: BaselineChecks.Run
    private let pending: PendingUpdates
    private let now: @Sendable () -> Int

    public init(sshdConfig: SshdConfigResolver, files: MacFiles, homeDirectory: String, run: @escaping BaselineChecks.Run, pending: PendingUpdates,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.config = sshdConfig; self.files = files; self.homeDirectory = homeDirectory; self.run = run; self.pending = pending; self.now = now
    }

    public func answer(_ query: SecurityQuery) async throws -> SecurityAnswer {
        SecurityAnswer(cursor: SecurityCursor.encode(now()), reset: false, events: [], baseline: await baseline())
    }

    /// Waits for the slow update count (the route never does), for a one-off dump.
    public func refreshPendingUpdates() async { await pending.refresh() }

    public func baseline() async -> SecurityBaseline {
        SecurityBaseline(passwordLogin: config.passwordLogin(), banTool: .notAvailable, firewall: await BaselineChecks.firewall(run: run),
                         autoUpdates: await BaselineChecks.autoUpdates(run: run),
                         startsAfterReboot: await BaselineChecks.startsAfterReboot(files: files, homeDirectory: homeDirectory, run: run),
                         pendingUpdates: pending.current())
    }
}
