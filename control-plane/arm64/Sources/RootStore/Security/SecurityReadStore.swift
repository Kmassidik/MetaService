import Foundation
import RootCore

/// A block that may still be in force; the caller checks `until` against the clock.
public struct SecurityBlockCandidate: Equatable, Sendable {
    public let machine: String
    public let address: String
    public let since: String
    public let until: String?
    public let attempts: Int?
}

/// The reading side of the security log, for the Overview. All SQL is fixed text with bound values.
extension SecurityStore {
    public static let topRows = 8
    private static let maxBlockedRows = 500

    /// Failed logins per machine on the days from `firstDay` on.
    public func failedTotals(sinceDay firstDay: String) throws -> [String: Int] {
        let rows = try database.query("SELECT machine, SUM(count) AS total FROM failed_daily WHERE day >= ? GROUP BY machine", [.text(firstDay)])
        return Dictionary(rows.map { ($0.string("machine"), $0.int("total")) }, uniquingKeysWith: { first, _ in first })
    }

    /// Blocks per machine since a time.
    public func blockedTotals(since start: Date) throws -> [String: Int] {
        let rows = try database.query("SELECT machine, COUNT(*) AS total FROM events WHERE type = 'blocked' AND time >= ? GROUP BY machine", [.text(SecurityTime.text(start))])
        return Dictionary(rows.map { ($0.string("machine"), $0.int("total")) }, uniquingKeysWith: { first, _ in first })
    }

    public func topUsers(sinceDay firstDay: String) throws -> [SecurityTopRow] {
        try database.query("""
            SELECT user AS name, SUM(count) AS total FROM failed_daily WHERE day >= ? AND user != '' GROUP BY user ORDER BY total DESC, name ASC LIMIT ?
            """, [.text(firstDay), .int(Self.topRows)]).map { SecurityTopRow(name: $0.string("name"), count: $0.int("total")) }
    }

    public func topAddresses(sinceDay firstDay: String) throws -> [SecurityTopRow] {
        try database.query("""
            SELECT address AS name, SUM(count) AS total FROM failed_daily WHERE day >= ? AND address != '' GROUP BY address ORDER BY total DESC, name ASC LIMIT ?
            """, [.text(firstDay), .int(Self.topRows)]).map { SecurityTopRow(name: $0.string("name"), count: $0.int("total")) }
    }

    /// Failed logins per day and machine, oldest day first. A day without a count has no row.
    public func daily(sinceDay firstDay: String) throws -> [SecurityDailyRow] {
        try database.query("SELECT day, machine, SUM(count) AS total FROM failed_daily WHERE day >= ? GROUP BY day, machine ORDER BY day ASC, machine ASC", [.text(firstDay)])
            .map { SecurityDailyRow(day: $0.string("day"), machine: $0.string("machine"), failed: $0.int("total")) }
    }

    /// The addresses whose latest block/unblock event is a block. `attempts` adds up the failed logins from that address on that machine since `firstDay`.
    public func blockCandidates(attemptsSinceDay firstDay: String) throws -> [SecurityBlockCandidate] {
        let rows = try database.query("""
            SELECT machine, address, time, until_time, (SELECT SUM(f.count) FROM failed_daily f WHERE f.machine = latest.machine AND f.address = latest.address AND f.day >= ?) AS attempts
            FROM (
              SELECT machine, address, time, until_time, type, ROW_NUMBER() OVER (PARTITION BY machine, address ORDER BY time DESC, id DESC) AS position
              FROM events WHERE type IN ('blocked', 'unblocked') AND address IS NOT NULL
            ) AS latest
            WHERE position = 1 AND type = 'blocked' ORDER BY time DESC LIMIT ?
            """, [.text(firstDay), .int(Self.maxBlockedRows)])
        return rows.map { SecurityBlockCandidate(machine: $0.string("machine"), address: $0.string("address"), since: $0.string("time"), until: $0.optionalString("until_time"), attempts: $0.optionalInt("attempts")) }
    }
}

/// The rule for "blocked now": the latest event of the address is a block, and the ban has no end or the end is still ahead.
public enum SecurityBlocking {
    public static func inForce(_ candidates: [SecurityBlockCandidate], now: Date) -> [SecurityBlockedRow] {
        candidates.filter { stillBlocked(until: $0.until, now: now) }
            .map { SecurityBlockedRow(machine: $0.machine, address: $0.address, since: $0.since, until: $0.until, attempts: $0.attempts) }
    }

    static func stillBlocked(until: String?, now: Date) -> Bool {
        guard let until else { return true }
        guard let end = SecurityTime.parse(until) else { return false }
        return end > now
    }
}
