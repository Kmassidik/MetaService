import Foundation
import MSCore

/// What one helper call came to.
public enum ReadingOutcome<Value: Sendable>: Sendable {
    case fresh(Value)
    /// The helper is there but has no stats route yet.
    case oldHelper
    case unreachable
}

public enum ReadingKind: Equatable, Sendable {
    case fresh
    case oldHelper
    case unreachable
}

/// What a request gets: how the last call went, and the newest good numbers (the last ones are kept after a failure, so the panel can grey them).
public struct Reading<Value: Sendable>: Sendable {
    public let answer: ReadingKind
    public let value: Value?
    public let fetchedAt: Date?

    public init(answer: ReadingKind, value: Value?, fetchedAt: Date?) {
        self.answer = answer
        self.value = value
        self.fetchedAt = fetchedAt
    }
}

extension Reading where Value == MachineStats {
    /// The same reading with the process list left out.
    public func withoutProcesses() -> Reading<MachineStats> {
        Reading(answer: answer, value: value?.withoutProcesses(), fetchedAt: fetchedAt)
    }
}

/// One shared reading per machine, however many tabs ask (docs/monitor-contract.md, "Shared reading").
/// A helper is called at most once per `sharedReadingSeconds`; askers that arrive during a call wait for that call; a reading nobody asked for in `dropSeconds` is thrown away.
public actor SharedReadings<Value: Sendable> {
    /// Short enough that a person polling every 2 seconds gets a new helper reading each time, long enough that two browser tabs and the history sampler share one.
    public static var sharedReadingSeconds: TimeInterval { 1.5 }
    public static var dropSeconds: TimeInterval { 30 }

    private struct Entry {
        var lastAsked: Date
        var attemptedAt: Date?
        var kind: ReadingKind = .unreachable
        /// The last call asked for the extra part (the process list); such a reading also answers a request without it.
        var detailed = false
        var good: (value: Value, at: Date)?
        var inFlight: Task<Void, Never>?
    }

    private let clock: Clock
    private var entries: [String: Entry] = [:]

    public init(clock: Clock) {
        self.clock = clock
    }

    public var heldCount: Int { entries.count }

    /// The reading for a machine; calls `fetch` only when the shared one is older than `sharedReadingSeconds` and nobody is already fetching.
    /// `detailed` says the asker wants the extra part (the process list). A held detailed reading answers everybody; a held plain one does not answer a detailed
    /// request, which then makes one call at once (a failed or old-helper reading is not repeated for it: a dead helper is left alone for `sharedReadingSeconds`).
    /// `keepsAlive` false is for a caller that is not a person watching (the history sampler): it shares the reading and its rate limit like anybody, but does not
    /// keep the reading from being dropped, so a machine nobody looks at still loses its held numbers after `dropSeconds`.
    public func read(_ key: String, detailed: Bool = false, keepsAlive: Bool = true, fetch: @escaping @Sendable () async -> ReadingOutcome<Value>) async -> Reading<Value> {
        let now = clock.now
        sweep(now)
        var entry = entries[key] ?? Entry(lastAsked: now)
        if keepsAlive { entry.lastAsked = now }
        entries[key] = entry
        while let running = entries[key]?.inFlight { await running.value }
        guard let current = entries[key], needsCall(current, detailed, clock.now) else { return snapshot(key) }
        let task = Task { await self.finish(key, detailed, await fetch()) }
        entries[key]?.inFlight = task
        await task.value
        return snapshot(key)
    }

    /// What is held for a machine without calling its helper (the machine is known to be offline). Asking keeps the reading alive.
    public func lastKnown(_ key: String) -> Reading<Value> {
        let now = clock.now
        sweep(now)
        entries[key]?.lastAsked = now
        return snapshot(key)
    }

    private func needsCall(_ entry: Entry, _ detailed: Bool, _ now: Date) -> Bool {
        guard let attempted = entry.attemptedAt else { return true }
        let lacksDetail = detailed && !entry.detailed && entry.kind == .fresh
        return lacksDetail || now.timeIntervalSince(attempted) >= Self.sharedReadingSeconds
    }

    private func finish(_ key: String, _ detailed: Bool, _ outcome: ReadingOutcome<Value>) {
        guard var entry = entries[key] else { return }
        entry.attemptedAt = clock.now
        entry.detailed = detailed
        entry.inFlight = nil
        switch outcome {
        case .fresh(let value): entry.kind = .fresh; entry.good = (value, clock.now)
        case .oldHelper: entry.kind = .oldHelper; entry.good = nil
        case .unreachable: entry.kind = .unreachable
        }
        entries[key] = entry
    }

    private func snapshot(_ key: String) -> Reading<Value> {
        guard let entry = entries[key] else { return Reading(answer: .unreachable, value: nil, fetchedAt: nil) }
        return Reading(answer: entry.kind, value: entry.good?.value, fetchedAt: entry.good?.at)
    }

    private func sweep(_ now: Date) {
        entries = entries.filter { $0.value.inFlight != nil || now.timeIntervalSince($0.value.lastAsked) <= Self.dropSeconds }
    }
}
