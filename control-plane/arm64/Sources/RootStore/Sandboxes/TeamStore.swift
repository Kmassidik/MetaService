import Foundation
import RootCore

/// Sandbox teams: who may make sandboxes, and with what limits. One small store, one topic (see sandbox/README.md,
/// "Teams, keys and limits"). A team has no sign-up; an operator makes it in the panel.
public struct TeamStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Makes a team with its limits fixed at the start. A duplicate id or name throws the database's constraint error.
    @discardableResult
    public func create(id: String, name: String, limits: TeamLimits = .standard, now: Date) throws -> TeamRecord {
        try database.execute("""
            INSERT INTO teams (id, name, created_at, max_running, max_vcpu, max_ram_mb, max_sandboxes_per_hour) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, [.text(id), .text(name), .int(Int(now.timeIntervalSince1970)), .int(limits.maxRunning), .int(limits.maxVcpu),
                  .int(limits.maxRamMb), .int(limits.maxSandboxesPerHour)])
        return TeamRecord(id: id, name: name, createdAt: now, limits: limits)
    }

    public func get(_ id: String) throws -> TeamRecord? {
        try database.query("SELECT id, name, created_at, max_running, max_vcpu, max_ram_mb, max_sandboxes_per_hour FROM teams WHERE id = ?",
                           [.text(id)]).first.map(Self.record)
    }

    /// The team's name, used by the panel and the audit log; nil when the team is gone.
    public func name(of team: String) throws -> String? {
        try database.query("SELECT name FROM teams WHERE id = ?", [.text(team)]).first?.string("name")
    }

    public func limits(of team: String) throws -> TeamLimits? {
        try get(team)?.limits
    }

    /// Every team, by name, for the panel.
    public func list() throws -> [TeamRecord] {
        try database.query("SELECT id, name, created_at, max_running, max_vcpu, max_ram_mb, max_sandboxes_per_hour FROM teams ORDER BY name")
            .map(Self.record)
    }

    /// Changes a team's limits. False when there is no such team.
    @discardableResult
    public func setLimits(_ limits: TeamLimits, team: String) throws -> Bool {
        try database.execute("UPDATE teams SET max_running = ?, max_vcpu = ?, max_ram_mb = ?, max_sandboxes_per_hour = ? WHERE id = ?",
                             [.int(limits.maxRunning), .int(limits.maxVcpu), .int(limits.maxRamMb), .int(limits.maxSandboxesPerHour), .text(team)]) > 0
    }

    private static func record(_ row: Row) -> TeamRecord {
        TeamRecord(id: row.string("id"), name: row.string("name"), createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))),
                   limits: TeamLimits(maxRunning: row.int("max_running"), maxVcpu: row.int("max_vcpu"), maxRamMb: row.int("max_ram_mb"),
                                      maxSandboxesPerHour: row.int("max_sandboxes_per_hour")))
    }
}
