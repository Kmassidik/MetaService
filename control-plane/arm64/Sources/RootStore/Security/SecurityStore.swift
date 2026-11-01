import Foundation
import RootCore

/// What the log knows about one machine.
public struct SecurityMachineState: Equatable, Sendable {
    public let cursor: String?
    public let lastReported: String?
    public let baseline: SecurityBaseline
}

/// The writing side of the security log: pages of events in, old rows out.
public final class SecurityStore: SecurityLedger, @unchecked Sendable {
    let database: Database

    public init(_ database: Database) {
        self.database = database
    }

    public func cursor(machine: String) throws -> String? {
        try state(machine: machine)?.cursor
    }

    public func state(machine: String) throws -> SecurityMachineState? {
        try database.query("SELECT cursor, last_reported, baseline_json FROM machine_state WHERE machine = ?", [.text(machine)]).first.map(Self.state)
    }

    public func states() throws -> [String: SecurityMachineState] {
        let rows = try database.query("SELECT machine, cursor, last_reported, baseline_json FROM machine_state")
        return Dictionary(rows.map { ($0.string("machine"), Self.state($0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Stores one page and moves the cursor in the same transaction: after a crash the page is either wholly in with its cursor, or wholly out and asked for again.
    /// A reset only stores the new cursor; nothing already stored is deleted. Failed logins are added to the day's count and not stored one by one.
    public func store(_ pull: SecurityPull, machine: String, now: Date) throws {
        let oldest = SecurityTime.retentionCutoff(now: now)
        let bucketsOldest = SecurityTime.bucketRetentionCutoff(now: now)
        try database.transaction {
            for event in pull.events where event.time >= oldest {
                try add(event, machine: machine, bucketsFrom: bucketsOldest)
            }
            try database.execute("""
                INSERT INTO machine_state (machine, cursor, last_reported, baseline_json) VALUES (?, ?, ?, ?)
                ON CONFLICT(machine) DO UPDATE SET cursor = excluded.cursor, last_reported = excluded.last_reported, baseline_json = excluded.baseline_json
                """, [.text(machine), .text(pull.cursor), .text(SecurityTime.text(now)), .text(Self.json(pull.baseline))])
        }
    }

    /// Deletes what is older than the retention. A machine that was removed from the panel keeps its rows until then.
    @discardableResult
    public func prune(now: Date) throws -> Int {
        let cutoff = SecurityTime.retentionCutoff(now: now)
        return try database.transaction {
            let events = try database.execute("DELETE FROM events WHERE time < ?", [.text(SecurityTime.text(cutoff))])
            let failed = try database.execute("DELETE FROM failed_daily WHERE day < ?", [.text(SecurityTime.day(cutoff))])
            let buckets = try database.execute("DELETE FROM failed_buckets WHERE bucket_start < ?", [.text(SecurityTime.text(SecurityTime.bucketRetentionCutoff(now: now)))])
            let states = try database.execute("DELETE FROM machine_state WHERE last_reported < ?", [.text(SecurityTime.text(cutoff))])
            return events + failed + buckets + states
        }
    }

    private func add(_ event: SecurityHelperEvent, machine: String, bucketsFrom: Date) throws {
        guard event.type != .failedLogin else { return try addFailed(event, machine: machine, bucketsFrom: bucketsFrom) }
        try database.execute("""
            INSERT INTO events (time, machine, type, user, address, method, detail, until_time, count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1)
            """, [.text(SecurityTime.text(event.time)), .text(machine), .text(event.type.rawValue), Self.text(event.user), Self.text(event.address),
                  Self.text(event.method), Self.text(event.detail), Self.text(event.until.map(SecurityTime.text))])
    }

    private func addFailed(_ event: SecurityHelperEvent, machine: String, bucketsFrom: Date) throws {
        try addFailedDay(event, machine: machine)
        guard event.time >= bucketsFrom else { return }
        try addFailedBucket(event, machine: machine)
    }

    private func addFailedBucket(_ event: SecurityHelperEvent, machine: String) throws {
        try database.execute("""
            INSERT INTO failed_buckets (bucket_start, machine, user, address, count, last_seen) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(bucket_start, machine, user, address) DO UPDATE SET count = count + excluded.count, last_seen = MAX(last_seen, excluded.last_seen)
            """, [.text(SecurityTime.bucketStart(event.time)), .text(machine), .text(event.user ?? ""), .text(event.address ?? ""), .int(event.count), .text(SecurityTime.text(event.time))])
    }

    private func addFailedDay(_ event: SecurityHelperEvent, machine: String) throws {
        try database.execute("""
            INSERT INTO failed_daily (day, machine, user, address, count, last_seen) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(day, machine, user, address) DO UPDATE SET count = count + excluded.count, last_seen = MAX(last_seen, excluded.last_seen)
            """, [.text(SecurityTime.day(event.time)), .text(machine), .text(event.user ?? ""), .text(event.address ?? ""), .int(event.count), .text(SecurityTime.text(event.time))])
    }

    static func text(_ value: String?) -> SQLValue { value.map(SQLValue.text) ?? .null }

    private static func json(_ baseline: SecurityBaseline) -> String {
        (try? JSONEncoder().encode(baseline)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func state(_ row: Row) -> SecurityMachineState {
        let baseline = row.optionalString("baseline_json").flatMap { try? JSONDecoder().decode(SecurityBaseline.self, from: Data($0.utf8)) }
        return SecurityMachineState(cursor: row.optionalString("cursor"), lastReported: row.optionalString("last_reported"), baseline: baseline ?? .unknown)
    }
}
