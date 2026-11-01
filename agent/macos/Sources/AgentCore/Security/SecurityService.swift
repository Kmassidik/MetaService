import Foundation

/// What `GET /v1/security/events` answers: the connection events since the cursor, and the baseline of the machine.
public final class SecurityService {
    private let reader: SecurityEventsReader
    private let config: SshdConfigResolver
    private let files: MacFiles
    private let homeDirectory: String
    private let run: BaselineChecks.Run
    private let pending: PendingUpdates

    public init(reader: SecurityEventsReader, sshdConfig: SshdConfigResolver, files: MacFiles, homeDirectory: String, run: @escaping BaselineChecks.Run, pending: PendingUpdates) {
        self.reader = reader; self.config = sshdConfig; self.files = files; self.homeDirectory = homeDirectory; self.run = run; self.pending = pending
    }

    public func answer(_ query: SecurityQuery) async throws -> SecurityAnswer {
        let page = try await reader.read(after: query.after, limit: query.limit)
        return SecurityAnswer(cursor: page.cursor, reset: page.reset, events: page.events, baseline: await baseline())
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
