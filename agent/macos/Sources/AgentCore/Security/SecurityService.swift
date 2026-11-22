import Foundation

/// What `GET /v1/security/events` answers: the baseline of the machine, plus failed-login events
/// when sshd logs VERBOSE (docs/security-model.md). Without VERBOSE, macOS logs no user or
/// address for SSH, so the agent reports no events; attempts are counted where the OS can see them.
public final class SecurityService {
    private let config: SshdConfigResolver
    private let files: MacFiles
    private let homeDirectory: String
    private let run: BaselineChecks.Run
    private let pending: PendingUpdates
    private let now: @Sendable () -> Int
    /// Tails the sshd -E log; nil when the caller has no way to read it (tests).
    private let tail: SshFileTailSource?
    /// The file offset the last read stopped at (in-memory; the parent's cursor carries it across restarts).
    private var offset: Int = 0
    /// (user, address) pairs already reported, so the two lines of one connection yield one event.
    private var pidDedupe: [Int: String] = [:]

    public init(sshdConfig: SshdConfigResolver, files: MacFiles, homeDirectory: String, run: @escaping BaselineChecks.Run, pending: PendingUpdates,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
                tail: SshFileTailSource? = SshFileTailSource()) {
        self.config = sshdConfig; self.files = files; self.homeDirectory = homeDirectory; self.run = run; self.pending = pending; self.now = now; self.tail = tail
    }

    public func answer(_ query: SecurityQuery) async throws -> SecurityAnswer {
        let after = query.after.flatMap { SecurityCursor.decode($0) } ?? 0
        let read = tail?.events(afterOffset: after, pidDedupe: &pidDedupe) ?? (events: [], offset: after, reset: false)
        offset = read.offset
        let cursor = SecurityCursor.encode(offset)
        return SecurityAnswer(cursor: cursor, reset: false, events: read.events, baseline: await baseline())
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
