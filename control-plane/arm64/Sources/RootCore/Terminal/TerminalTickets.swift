import Foundation
import MSCore

/// What a ticket opens: one VM on one machine.
public struct ConsoleKey: Hashable, Sendable {
    public let machine: String
    public let workload: String

    public init(machine: String, workload: String) {
        self.machine = machine
        self.workload = workload
    }
}

/// One-time passes for the console socket. A ticket belongs to the operator who asked, lives 30 seconds, and works once.
/// Only a hash of each ticket is kept, so looking one up never compares the secret itself.
public final class TerminalTickets: @unchecked Sendable {
    public static let lifetimeSeconds = 30

    private struct Entry {
        let operatorName: String
        let key: ConsoleKey
        let expires: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init() {}

    public func issue(token: String, operatorName: String, key: ConsoleKey, now: Date) {
        lock.withLock {
            entries = entries.filter { $0.value.expires > now }
            entries[Tokens.sha256Hex(token)] = Entry(operatorName: operatorName, key: key, expires: now.addingTimeInterval(TimeInterval(Self.lifetimeSeconds)))
        }
    }

    /// The console a ticket opens, or nil. Any try burns the ticket, whoever made it and whether or not it was right.
    public func redeem(token: String, operatorName: String, now: Date) -> ConsoleKey? {
        let entry = lock.withLock { entries.removeValue(forKey: Tokens.sha256Hex(token)) }
        guard let entry, entry.expires > now, entry.operatorName == operatorName else { return nil }
        return entry.key
    }
}
