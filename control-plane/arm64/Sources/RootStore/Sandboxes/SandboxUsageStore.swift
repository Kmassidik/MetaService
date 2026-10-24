import Foundation
import RootCore

/// One finished run of a sandbox, as the ledger keeps it: when it ran and what it used. Never the key, never the program.
public struct SandboxUsageRow: Encodable, Equatable {
    public let team: String
    public let sandbox: String
    public let startedAt: Date
    public let endedAt: Date
    public let totals: SandboxUsageTotals

    public init(team: String, sandbox: String, startedAt: Date, endedAt: Date, totals: SandboxUsageTotals) {
        self.team = team
        self.sandbox = sandbox
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totals = totals
    }

    enum CodingKeys: String, CodingKey { case team, sandbox, startedAt, endedAt, seconds, vcpuSeconds, ramMbSeconds }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(team, forKey: .team)
        try box.encode(sandbox, forKey: .sandbox)
        try box.encode(Dates.iso(Int(startedAt.timeIntervalSince1970)), forKey: .startedAt)
        try box.encode(Dates.iso(Int(endedAt.timeIntervalSince1970)), forKey: .endedAt)
        try box.encode(totals.seconds, forKey: .seconds)
        try box.encode(totals.vcpuSeconds, forKey: .vcpuSeconds)
        try box.encode(totals.ramMbSeconds, forKey: .ramMbSeconds)
    }
}

/// The usage ledger next to the token ledger: one row for each finished sandbox run. The arithmetic is
/// `SandboxUsageMath`'s, so the row and the tests compute the same numbers.
public struct SandboxUsageStore {
    private let database: Database
    public static let maxList = 1_000

    public init(_ database: Database) { self.database = database }

    /// Adds one finished run. A run that did not advance (a helper clock behind the parent's) counts zero seconds.
    @discardableResult
    public func record(team: String, sandbox: String, startedAt: Date, endedAt: Date, shape: SandboxShape) throws -> SandboxUsageRow {
        let totals = SandboxUsageMath.totals(from: startedAt, to: endedAt, shape: shape)
        try database.execute("""
            INSERT INTO sandbox_usage (team, sandbox, started_at, ended_at, seconds, vcpu_seconds, ram_mb_seconds) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [.text(team), .text(sandbox), .int(Int(startedAt.timeIntervalSince1970)), .int(Int(endedAt.timeIntervalSince1970)),
                  .int(totals.seconds), .int(totals.vcpuSeconds), .int(totals.ramMbSeconds)])
        return SandboxUsageRow(team: team, sandbox: sandbox, startedAt: startedAt, endedAt: endedAt, totals: totals)
    }

    /// A team's runs, newest first, for the panel.
    public func list(team: String, limit: Int = 100) throws -> [SandboxUsageRow] {
        let size = min(max(limit, 1), Self.maxList)
        return try database.query("""
            SELECT team, sandbox, started_at, ended_at, seconds, vcpu_seconds, ram_mb_seconds FROM sandbox_usage
            WHERE team = ? ORDER BY ended_at DESC, id DESC LIMIT ?
            """, [.text(team), .int(size)]).map {
            SandboxUsageRow(team: $0.string("team"), sandbox: $0.string("sandbox"),
                            startedAt: Date(timeIntervalSince1970: TimeInterval($0.int("started_at"))),
                            endedAt: Date(timeIntervalSince1970: TimeInterval($0.int("ended_at"))),
                            totals: SandboxUsageTotals(seconds: $0.int("seconds"), vcpuSeconds: $0.int("vcpu_seconds"),
                                                       ramMbSeconds: $0.int("ram_mb_seconds")))
        }
    }

    /// The team's totals between two moments, both included. Pass distant dates for an open range.
    public func totals(team: String, from: Date = .distantPast, to: Date = .distantFuture) throws -> SandboxUsageTotals {
        let row = try database.query("""
            SELECT COALESCE(SUM(seconds), 0) AS seconds, COALESCE(SUM(vcpu_seconds), 0) AS vcpu_seconds,
                   COALESCE(SUM(ram_mb_seconds), 0) AS ram_mb_seconds
            FROM sandbox_usage WHERE team = ? AND ended_at >= ? AND ended_at <= ?
            """, [.text(team), .int(Int(from.timeIntervalSince1970)), .int(Int(to.timeIntervalSince1970))]).first
        return SandboxUsageTotals(seconds: row?.int("seconds") ?? 0, vcpuSeconds: row?.int("vcpu_seconds") ?? 0,
                                  ramMbSeconds: row?.int("ram_mb_seconds") ?? 0)
    }
}
