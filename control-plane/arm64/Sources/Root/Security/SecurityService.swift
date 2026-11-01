import Foundation
import MSCore
import RootCore
import RootStore

/// Asks a helper for a page of security events through the same tunnel and client the stats use.
struct AgentSecuritySource: SecurityHelperSource {
    let client: AgentClient

    static let helperTimeoutSeconds: TimeInterval = 10
    private static let maxReplyBytes = 2 * 1024 * 1024
    private static let cursorSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    func fetch(machine: String, after: String?, limit: Int) async -> SecurityFetch {
        var path = "/v1/security/events?limit=\(limit)"
        if let after, let encoded = after.addingPercentEncoding(withAllowedCharacters: Self.cursorSafe) { path += "&after=\(encoded)" }
        guard let reply = try? await client.call(machine: machine, method: "GET", path: path, timeout: Self.helperTimeoutSeconds, maxBytes: Self.maxReplyBytes) else { return .unreachable }
        return .reply(status: reply.status, data: reply.data)
    }
}

/// Pulls the security events of the watched machines in the background and answers the two Security routes.
final class SecurityService: Sendable {
    private let machines: MachineStore
    private let store: SecurityStore
    private let puller: SecurityPuller
    private let clock: Clock
    private let pollSeconds: Int

    init(machines: MachineStore, store: SecurityStore, client: AgentClient, clock: Clock, pollSeconds: Int) {
        self.machines = machines
        self.store = store
        self.clock = clock
        self.pollSeconds = pollSeconds
        puller = SecurityPuller(helper: AgentSecuritySource(client: client), ledger: store, clock: clock) { line in
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// Deletes what is too old now, then starts the loop that asks the machines every `pollSeconds`. The loop runs for as long as the parent does.
    func start() {
        prune()
        Task.detached { await self.run() }
    }

    private func run() async {
        var lastPrune = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollSeconds) * 1_000_000_000)
            if SecurityTime.retentionDue(lastRun: lastPrune, now: clock.now) {
                prune()
                lastPrune = clock.now
            }
            await puller.tick(machines: watchedMachines())
        }
    }

    /// The machines that can answer (online or busy) and whose helper says it serves security events.
    func watchedMachines() -> [String] {
        let all = (try? machines.list(now: clock.now)) ?? []
        return all.filter { SecurityPuller.isWatched(state: $0.state, serves: $0.capabilities?.security) }.map(\.id)
    }

    private func prune() {
        do {
            try store.prune(now: clock.now)
        } catch {
            FileHandle.standardError.write(Data("security: old rows could not be deleted: \(error)\n".utf8))
        }
    }

    func overview(range: SecurityRange) throws -> SecurityOverviewReply {
        let now = clock.now
        let known = try machines.list(now: now)
        let ids = Set(known.map(\.id))
        let window = range.window(now: now)
        let states = try store.states()
        let failed = try store.failedTotals(in: window)
        let blocked = try store.blockedTotals(since: range.start(now: now))
        let lines = known.map { machine -> SecurityMachineLine in
            guard machine.capabilities?.security == true, let state = states[machine.id], let reported = state.lastReported else { return .notWatched(machine.id) }
            return SecurityMachineLine(machine: machine.id, reported: true, lastReported: reported, baseline: state.baseline, failed: failed[machine.id] ?? 0, blocked: blocked[machine.id] ?? 0)
        }
        let watched = Set(lines.filter(\.reported).map(\.machine))
        let series = try failedSeries(range: range, window: window, watched: watched)
        return SecurityOverviewReply(
            range: range.rawValue, generatedAt: SecurityTime.text(now), machines: lines,
            blockedNow: SecurityBlocking.inForce(try store.blockCandidates(attemptsIn: window), now: now).filter { ids.contains($0.machine) },
            topUsers: try store.topUsers(in: window), topAddresses: try store.topAddresses(in: window),
            daily: series.daily, buckets: series.buckets)
    }

    /// The chart data of a range: ten-minute buckets up to 24 hours, UTC days for longer ranges; only watched machines, and the other kind stays empty.
    private func failedSeries(range: SecurityRange, window: SecurityWindow, watched: Set<String>) throws -> (daily: [SecurityDailyRow], buckets: [SecurityBucketRow]) {
        guard case .buckets(let first) = window else {
            return (try store.daily(sinceDay: range.firstDay(now: clock.now)).filter { watched.contains($0.machine) }, [])
        }
        return ([], try store.buckets(from: first).filter { watched.contains($0.machine) })
    }

    func events(_ query: SecurityQuery) throws -> SecurityEventsReply {
        try store.eventsPage(query, now: clock.now)
    }
}
