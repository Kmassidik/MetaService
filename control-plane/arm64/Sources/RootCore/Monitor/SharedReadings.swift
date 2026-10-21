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

/// One shared reading per machine, however many tabs ask (docs/monitor-contract.md, "Shared reading").
/// A helper is called at most once per `refreshSeconds`; askers that arrive during a call wait for that call; a reading nobody asked for in `dropSeconds` is thrown away.
public actor SharedReadings<Value: Sendable> {
    public static var refreshSeconds: TimeInterval { 4 }
    public static var dropSeconds: TimeInterval { 30 }

    private struct Entry {
        var lastAsked: Date
        var attemptedAt: Date?
        var kind: ReadingKind = .unreachable
        var good: (value: Value, at: Date)?
        var inFlight: Task<Void, Never>?
    }

    private let clock: Clock
    private var entries: [String: Entry] = [:]

    public init(clock: Clock) {
        self.clock = clock
    }

    public var heldCount: Int { entries.count }

    /// The reading for a machine; calls `fetch` only when the shared one is older than `refreshSeconds` and nobody is already fetching.
    public func read(_ key: String, fetch: @escaping @Sendable () async -> ReadingOutcome<Value>) async -> Reading<Value> {
        let now = clock.now
        sweep(now)
        var entry = entries[key] ?? Entry(lastAsked: now)
        entry.lastAsked = now
        entries[key] = entry
        if let running = entry.inFlight { await running.value; return snapshot(key) }
        guard isStale(entry, now) else { return snapshot(key) }
        let task = Task { await self.finish(key, await fetch()) }
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

    private func isStale(_ entry: Entry, _ now: Date) -> Bool {
        guard let attempted = entry.attemptedAt else { return true }
        return now.timeIntervalSince(attempted) >= Self.refreshSeconds
    }

    private func finish(_ key: String, _ outcome: ReadingOutcome<Value>) {
        guard var entry = entries[key] else { return }
        entry.attemptedAt = clock.now
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
