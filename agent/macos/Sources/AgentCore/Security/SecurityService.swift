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
    /// Reads the VERBOSE sshd log for one window; nil when the caller has no way to read the log (tests).
    private let readLog: (@Sendable (_ start: Int, _ end: Int, _ timeout: TimeInterval) async throws -> String)?
    private var reader: VerboseEventsReader?

    public init(sshdConfig: SshdConfigResolver, files: MacFiles, homeDirectory: String, run: @escaping BaselineChecks.Run, pending: PendingUpdates,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) },
                uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                readLog: (@Sendable (_ start: Int, _ end: Int, _ timeout: TimeInterval) async throws -> String)? = nil) {
        self.config = sshdConfig; self.files = files; self.homeDirectory = homeDirectory; self.run = run; self.pending = pending; self.now = now; self.readLog = readLog
        if let readLog { self.reader = VerboseEventsReader(now: now, uptime: uptime, readLog: readLog) }
    }

    public func answer(_ query: SecurityQuery) async throws -> SecurityAnswer {
        let events = await withLog()
        return SecurityAnswer(cursor: SecurityCursor.encode(now()), reset: false, events: events, baseline: await baseline())
    }

    /// One page of events, or none when sshd does not log VERBOSE (or the log cannot be read): the machine is honest about what it can see.
    private func withLog() async -> [SecurityEvent] {
        guard config.logLevel()?.hasPrefix("verbose") == true, let reader = reader else { return [] }
        return (try? await reader.read(after: nil, limit: 2000))?.events ?? []
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
