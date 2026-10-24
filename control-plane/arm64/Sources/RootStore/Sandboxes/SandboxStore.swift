import Foundation
import RootCore

public enum SandboxStoreError: Error, Equatable {
    case unknownState(String)
}

/// The parent's record of every sandbox it accepted, alive or ended, and the team usage the limits are checked against.
/// One topic: the sandboxes table (see sandbox/README.md). The helper's own facts are read for placement, not from here.
public struct SandboxStore {
    private let database: Database
    /// The most rows one list answers with. The public API pages at 100; the panel asks for more.
    public static let maxList = 500

    public init(_ database: Database) { self.database = database }

    /// Checks the team's limits and writes the record as one step, so two creates at once cannot both count the same
    /// free room. Throws `TeamLimitRefusal` when a limit would be broken, or the database's constraint error for a
    /// duplicate id.
    @discardableResult
    public func create(_ new: NewSandbox, limits: TeamLimits, now: Date) throws -> SandboxRecord {
        try database.transaction {
            if let refusal = SandboxLimits.refusal(limits, usage: try teamUsage(team: new.team, now: now), shape: new.shape) { throw refusal }
            try database.execute("""
                INSERT INTO sandboxes (id, team, machine, state, template, vcpu, ram_mb, disk_mb, created_at, end_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(new.id), .text(new.team), .text(new.machine), .text(new.state.rawValue), .text(new.template),
                      .int(new.shape.vcpu), .int(new.shape.ramMb), .int(new.shape.diskMb),
                      .int(Int(now.timeIntervalSince1970)), .int(Int(new.endAt.timeIntervalSince1970))])
            return SandboxRecord(id: new.id, team: new.team, machine: new.machine, state: new.state, template: new.template,
                                 vcpu: new.shape.vcpu, ramMb: new.shape.ramMb, diskMb: new.shape.diskMb, createdAt: now, endAt: new.endAt)
        }
    }

    public func get(id: String) throws -> SandboxRecord? {
        try database.query("""
            SELECT id, team, machine, state, template, vcpu, ram_mb, disk_mb, created_at, end_at, ended_at, ended_reason
            FROM sandboxes WHERE id = ?
            """, [.text(id)]).first.map(Self.record)
    }

    /// A team's sandboxes, newest first. The public list and the panel both read this.
    public func list(team: String, limit: Int = 100) throws -> [SandboxRecord] {
        let size = min(max(limit, 1), Self.maxList)
        return try database.query("""
            SELECT id, team, machine, state, template, vcpu, ram_mb, disk_mb, created_at, end_at, ended_at, ended_reason
            FROM sandboxes WHERE team = ? ORDER BY created_at DESC, id DESC LIMIT ?
            """, [.text(team), .int(size)]).map(Self.record)
    }

    /// What the team already uses: running sandboxes and what they hold, and how many were made in the last hour.
    /// The states are the ones `SandboxState.holdsCompute` names; paused sandboxes hold neither a slot nor memory.
    public func teamUsage(team: String, now: Date) throws -> TeamUsage {
        let totals = try database.query("""
            SELECT
              COALESCE(SUM(CASE WHEN state IN ('starting', 'running', 'pausing', 'resuming', 'stopping') THEN 1 ELSE 0 END), 0) AS running,
              COALESCE(SUM(CASE WHEN state IN ('starting', 'running', 'pausing', 'resuming', 'stopping') THEN vcpu ELSE 0 END), 0) AS vcpu,
              COALESCE(SUM(CASE WHEN state IN ('starting', 'running', 'pausing', 'resuming', 'stopping') THEN ram_mb ELSE 0 END), 0) AS ram_mb
            FROM sandboxes WHERE team = ?
            """, [.text(team)]).first
        let since = Int(now.addingTimeInterval(-Double(TeamLimits.hourlyWindowSeconds)).timeIntervalSince1970)
        let created = try database.query("SELECT COUNT(*) AS created FROM sandboxes WHERE team = ? AND created_at >= ?", [.text(team), .int(since)])
        return TeamUsage(running: totals?.int("running") ?? 0, vcpu: totals?.int("vcpu") ?? 0, ramMb: totals?.int("ram_mb") ?? 0,
                         createdLastHour: created.first?.int("created") ?? 0)
    }

    /// Marks a sandbox ended and remembers why and when. Ending one that already ended changes nothing; the record comes
    /// back as it stands, so a repeated end is harmless.
    public func end(id: String, at now: Date, reason: SandboxEndReason) throws -> SandboxRecord? {
        try database.execute("UPDATE sandboxes SET state = ?, ended_at = ?, ended_reason = ? WHERE id = ? AND ended_at IS NULL",
                             [.text(SandboxState.ended.rawValue), .int(Int(now.timeIntervalSince1970)), .text(reason.rawValue), .text(id)])
        return try get(id: id)
    }

    /// Moves a sandbox to another state while it is alive, as its helper reports it. Ending it is `end`, which also
    /// records why and when. False when there is no such sandbox, it has ended, or the state asked for is `ended`.
    @discardableResult
    public func setState(id: String, state: SandboxState) throws -> Bool {
        guard state.isAlive else { return false }
        return try database.execute("UPDATE sandboxes SET state = ? WHERE id = ? AND ended_at IS NULL", [.text(state.rawValue), .text(id)]) > 0
    }

    /// Moves the end time, after `SandboxEndTime` has checked it. False when there is no such sandbox, or it has ended.
    @discardableResult
    public func moveEnd(id: String, to endAt: Date) throws -> Bool {
        try database.execute("UPDATE sandboxes SET end_at = ? WHERE id = ? AND ended_at IS NULL",
                             [.int(Int(endAt.timeIntervalSince1970)), .text(id)]) > 0
    }

    private static func record(_ row: Row) throws -> SandboxRecord {
        let raw = row.string("state")
        guard let state = SandboxState(rawValue: raw) else { throw SandboxStoreError.unknownState(raw) }
        return SandboxRecord(id: row.string("id"), team: row.string("team"), machine: row.string("machine"), state: state,
                             template: row.string("template"), vcpu: row.int("vcpu"), ramMb: row.int("ram_mb"), diskMb: row.int("disk_mb"),
                             createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))),
                             endAt: Date(timeIntervalSince1970: TimeInterval(row.int("end_at"))),
                             endedAt: row.optionalInt("ended_at").map { Date(timeIntervalSince1970: TimeInterval($0)) },
                             endedReason: row.optionalString("ended_reason").flatMap(SandboxEndReason.init(rawValue:)))
    }
}
