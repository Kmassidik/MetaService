import Foundation

/// Why the book refused a new console.
public enum ConsoleRefusal: Error, Equatable {
    case alreadyOpen
    case tooMany
}

/// Who has a console open right now. One per VM, four in total, closed after 15 idle minutes or 8 hours.
/// A console is held from the moment its ticket is made, so two requests cannot both take the last place.
public final class TerminalSessions: @unchecked Sendable {
    public static let perVm = 1
    public static let total = 4
    public static let idleSeconds: TimeInterval = 15 * 60
    public static let longestSeconds: TimeInterval = 8 * 60 * 60

    private struct Entry {
        var holdUntil: Date?
        var opened: Date?
        var lastSeen: Date
        var ending: CloseReason?
    }

    private let lock = NSLock()
    private var entries: [ConsoleKey: Entry] = [:]

    public init() {}

    /// Holds a place for a console that has a ticket; the hold lapses with the ticket.
    public func reserve(_ key: ConsoleKey, now: Date) throws {
        try lock.withLock {
            entries = entries.filter { $0.value.opened != nil || ($0.value.holdUntil ?? .distantPast) > now }
            guard entries[key] == nil else { throw ConsoleRefusal.alreadyOpen }
            guard entries.count < Self.total else { throw ConsoleRefusal.tooMany }
            entries[key] = Entry(holdUntil: now.addingTimeInterval(TimeInterval(TerminalTickets.lifetimeSeconds)), opened: nil, lastSeen: now, ending: nil)
        }
    }

    /// The ticket was used: the held place becomes an open console. False when the hold is gone.
    public func open(_ key: ConsoleKey, now: Date) -> Bool {
        lock.withLock {
            guard var entry = entries[key], entry.opened == nil, (entry.holdUntil ?? .distantPast) > now else { return false }
            entry.opened = now
            entry.lastSeen = now
            entries[key] = entry
            return true
        }
    }

    public func touch(_ key: ConsoleKey, now: Date) {
        lock.withLock { entries[key]?.lastSeen = now }
    }

    /// Asks an open console to end for this reason; its bridge sees it on its next look.
    public func requestEnd(_ key: ConsoleKey, _ reason: CloseReason) {
        lock.withLock { entries[key]?.ending = reason }
    }

    public func requestEnd(machine: String, _ reason: CloseReason) {
        lock.withLock {
            for key in entries.keys where key.machine == machine { entries[key]?.ending = reason }
        }
    }

    /// The reason this console must end now, if any: asked to, too long, or idle.
    public func endReason(_ key: ConsoleKey, now: Date) -> CloseReason? {
        lock.withLock {
            guard let entry = entries[key], let opened = entry.opened else { return nil }
            if let ending = entry.ending { return ending }
            if now.timeIntervalSince(opened) >= Self.longestSeconds { return .tooLong }
            if now.timeIntervalSince(entry.lastSeen) >= Self.idleSeconds { return .idle }
            return nil
        }
    }

    /// Frees the place and says how many seconds the console was open (0 if it never opened).
    @discardableResult
    public func close(_ key: ConsoleKey, now: Date) -> Int {
        lock.withLock {
            guard let entry = entries.removeValue(forKey: key), let opened = entry.opened else { return 0 }
            return max(0, Int(now.timeIntervalSince(opened)))
        }
    }

    public var count: Int { lock.withLock { entries.count } }
}
