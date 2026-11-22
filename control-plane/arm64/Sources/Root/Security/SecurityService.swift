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
    private let client: AgentClient
    private let store: any SecurityLedger
    /// The concrete store for reads and retention pruning (not part of the ledger contract).
    private let concrete: SecurityStore
    private let puller: SecurityPuller
    private let clock: Clock
    private let pollSeconds: Int

    /// The rules engine: given the stored page, returns the notifications to send. Injected so tests can drive it.
    private let notify: SecurityNotifier?
    /// Last total failed count per machine, to detect a threshold crossing between pulls.
    private var lastCounts: [String: Int] = [:]

    init(machines: MachineStore, store: any SecurityLedger, pruner: SecurityStore?, client: AgentClient, clock: Clock, pollSeconds: Int, notify: SecurityNotifier? = nil) {
        self.machines = machines
        self.client = client
        self.store = store
        self.clock = clock
        self.pollSeconds = pollSeconds
        self.notify = notify
        self.concrete = pruner!
        puller = SecurityPuller(helper: AgentSecuritySource(client: client), ledger: store, clock: clock) { line in
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// Asks a machine's helper whether an address is currently in its pf blocklist.
    func banStatus(machine: String, address: String) async -> String? {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let reply = try? await client.call(machine: machine, method: "GET",
                                                 path: "/v1/security/ban-status?address=" + encoded,
                                                 timeout: 10, maxBytes: 4096) else { return nil }
        guard reply.status == 200 else { return nil }
        guard let body = try? JSONSerialization.jsonObject(with: reply.data) as? [String: Any] else { return nil }
        return (body["banned"] as? Bool) == true ? "banned" : "not_banned"
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
            try concrete.prune(now: clock.now)
        } catch {
            FileHandle.standardError.write(Data("security: old rows could not be deleted: \(error)\n".utf8))
        }
    }

    func overview(range: SecurityRange) throws -> SecurityOverviewReply {
        let now = clock.now
        let known = try machines.list(now: now)
        let ids = Set(known.map(\.id))
        let window = range.window(now: now)
        let states = try concrete.states()
        let failed = try concrete.failedTotals(in: window)
        let blocked = try concrete.blockedTotals(since: range.start(now: now))
        let lines = known.map { machine -> SecurityMachineLine in
            guard machine.capabilities?.security == true, let state = states[machine.id], let reported = state.lastReported else { return .notWatched(machine.id) }
            return SecurityMachineLine(machine: machine.id, reported: true, lastReported: reported, baseline: state.baseline, failed: failed[machine.id] ?? 0, blocked: blocked[machine.id] ?? 0)
        }
        let watched = Set(lines.filter(\.reported).map(\.machine))
        let series = try failedSeries(range: range, window: window, watched: watched)
        return SecurityOverviewReply(
            range: range.rawValue, generatedAt: SecurityTime.text(now), machines: lines,
            blockedNow: SecurityBlocking.inForce(try concrete.blockCandidates(attemptsIn: window), now: now).filter { ids.contains($0.machine) },
            topUsers: try concrete.topUsers(in: window), topAddresses: try concrete.topAddresses(in: window),
            daily: series.daily, buckets: series.buckets)
    }

    /// The chart data of a range: ten-minute buckets up to 24 hours, UTC days for longer ranges; only watched machines, and the other kind stays empty.
    private func failedSeries(range: SecurityRange, window: SecurityWindow, watched: Set<String>) throws -> (daily: [SecurityDailyRow], buckets: [SecurityBucketRow]) {
        guard case .buckets(let first) = window else {
            return (try concrete.daily(sinceDay: range.firstDay(now: clock.now)).filter { watched.contains($0.machine) }, [])
        }
        return ([], try concrete.buckets(from: first).filter { watched.contains($0.machine) })
    }

    func events(_ query: SecurityQuery) throws -> SecurityEventsReply {
        try concrete.eventsPage(query, now: clock.now)
    }
}
