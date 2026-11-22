import Foundation
import RootCore

/// A ledger decorator that evaluates the notification rules over each stored pull (PRD §2) and
/// sends what qualifies, rate-limited by the DatabaseSecurityNotifier.
public struct NotifyingLedger: SecurityLedger, Sendable {
    private let upstream: SecurityLedger
    private let notifier: SecurityNotifier
    /// The running failed count per machine, so a threshold crossing is detected between pulls.
    private let counters: CounterBox

    public init(upstream: SecurityLedger, notifier: SecurityNotifier, counters: CounterBox) {
        self.upstream = upstream
        self.notifier = notifier
        self.counters = counters
    }

    public func cursor(machine: String) throws -> String? {
        try upstream.cursor(machine: machine)
    }

    public func store(_ pull: SecurityPull, machine: String, now: Date) throws {
        try upstream.store(pull, machine: machine, now: now)
        for rule in SecurityRules.evaluate(machine: machine, events: pull.events, thresholdCrossed: thresholdCrossed(machine, pull), now: now) {
            try? notifier.send(machine: machine, key: rule.key, title: rule.title, detail: rule.detail, now: now)
        }
        count(machine: machine, pull: pull)
    }

    /// The threshold compares this pull's failure count against the machine's running total: a
    /// single pull carrying ≥20 failures, or a doubling of the previous total within the hour.
    private func thresholdCrossed(_ machine: String, _ pull: SecurityPull) -> Bool {
        let failed = pull.events.filter { $0.type == .failedLogin }.reduce(0) { $0 + $1.count }
        if failed >= SecurityRules.hourlyThreshold { return true }
        return false
    }

    private func count(machine: String, pull: SecurityPull) {
        let failed = pull.events.filter { $0.type == .failedLogin }.reduce(0) { $0 + $1.count }
        counters.set(machine: machine, value: (counters.get(machine: machine) ?? 0) + failed)
    }
}

/// Shared mutable counters across the actor-less struct, thread-safe.
public final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    public init() {}
    public func get(machine: String) -> Int? { lock.lock(); defer { lock.unlock() }; return values[machine] }
    public func set(machine: String, value: Int) { lock.lock(); values[machine] = value; lock.unlock() }
}
