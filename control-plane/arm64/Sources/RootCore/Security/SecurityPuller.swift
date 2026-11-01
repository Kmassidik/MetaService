import Foundation
import MSCore

/// What asking a helper for its security events gave back: its answer as it came, or nothing (unreachable, timed out).
public enum SecurityFetch: Sendable {
    case reply(status: Int, data: Data)
    case unreachable
}

/// Asks one helper for a page of events. The real one goes through the tunnel; a test gives a fake.
public protocol SecurityHelperSource: Sendable {
    func fetch(machine: String, after: String?, limit: Int) async -> SecurityFetch
}

/// Where the pulled events go. One call stores a whole page and moves the cursor in the same transaction.
public protocol SecurityLedger: Sendable {
    func cursor(machine: String) throws -> String?
    func store(_ pull: SecurityPull, machine: String, now: Date) throws
}

/// How one pull of a machine ended.
public enum SecurityPullOutcome: Equatable, Sendable {
    case pulled(pages: Int, events: Int)
    case failed(String)
}

/// Collects the security events of the machines that are watched. A failing machine never stops another one, and no error ends the loop.
public final class SecurityPuller: Sendable {
    public static let pageSize = 500
    public static let maxPagesPerTick = 5
    private static let okStatus = 200

    private let helper: SecurityHelperSource
    private let ledger: SecurityLedger
    private let clock: Clock
    private let report: @Sendable (String) -> Void
    private let failing = FailingSet()

    /// `report` receives one plain line when a machine starts failing or recovers (never a token, never helper text).
    public init(helper: SecurityHelperSource, ledger: SecurityLedger, clock: Clock, report: @escaping @Sendable (String) -> Void) {
        self.helper = helper
        self.ledger = ledger
        self.clock = clock
        self.report = report
    }

    /// A machine is asked when it can answer (online, or busy because VMs are running; not offline) and its helper says it serves security events.
    public static func isWatched(state: String, serves security: Bool?) -> Bool {
        state != "offline" && security == true
    }

    /// One tick: every machine at the same time, each limited to its own pages. Returns when all are done.
    public func tick(machines: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for machine in machines {
                group.addTask { self.noteOutcome(machine, await self.pull(machine)) }
            }
        }
    }

    /// Up to five pages while the helper answers full pages. Each page is stored with its cursor in one transaction, so a crash loses nothing and counts nothing twice.
    public func pull(_ machine: String) async -> SecurityPullOutcome {
        var pages = 0
        var events = 0
        while pages < Self.maxPagesPerTick, !Task.isCancelled {
            switch await page(machine) {
            case .failure(let failure): return .failed(failure.reason)
            case .success(let pull):
                pages += 1
                events += pull.events.count
                guard pull.received >= Self.pageSize else { return .pulled(pages: pages, events: events) }
            }
        }
        return .pulled(pages: pages, events: events)
    }

    private func page(_ machine: String) async -> Result<SecurityPull, SecurityPageFailure> {
        let after: String?
        do { after = try ledger.cursor(machine: machine) } catch { return .failure(SecurityPageFailure("the security database could not be read")) }
        guard case .reply(let status, let data) = await helper.fetch(machine: machine, after: after, limit: Self.pageSize) else {
            return .failure(SecurityPageFailure("the helper did not answer"))
        }
        guard status == Self.okStatus else { return .failure(SecurityPageFailure("the helper answered \(status)")) }
        let now = clock.now
        let pull: SecurityPull
        do { pull = try SecurityPull.parse(data, limit: Self.pageSize, now: now) } catch { return .failure(SecurityPageFailure("the helper answer was refused: \(error)")) }
        do { try ledger.store(pull, machine: machine, now: now) } catch { return .failure(SecurityPageFailure("the security database could not be written")) }
        return .success(pull)
    }

    private func noteOutcome(_ machine: String, _ outcome: SecurityPullOutcome) {
        switch outcome {
        case .pulled:
            if failing.remove(machine) { report("security: \(machine) answers again") }
        case .failed(let reason):
            if failing.insert(machine) { report("security: \(machine): \(reason)") }
        }
    }
}

/// A reason a page could not be pulled, in plain words without any text from the helper's body.
public struct SecurityPageFailure: Error, Equatable, Sendable {
    public let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// The machines that failed last time, so one line is written when a machine starts failing and one when it recovers, not one per minute.
private final class FailingSet: @unchecked Sendable {
    private let lock = NSLock()
    private var machines = Set<String>()

    /// True when the machine was not failing before.
    func insert(_ machine: String) -> Bool { lock.lock(); defer { lock.unlock() }; return machines.insert(machine).inserted }

    /// True when the machine was failing before.
    func remove(_ machine: String) -> Bool { lock.lock(); defer { lock.unlock() }; return machines.remove(machine) != nil }
}
