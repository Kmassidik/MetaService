import Foundation
import RootCore

public struct CommandRow: Encodable, Equatable {
    public let id: String
    public let machine: String
    public let workloadId: String?
    public let type: String
    public let state: String
    public let params: [String: String]
    public let result: [String: String]?
    public let actor: String
    public let createdAt: String
    public let finishedAt: String?
    /// Where the job is now, one of `JobSteps`; nil for a job with no steps and for rows from before steps existed.
    public let step: String?
    public let stepAt: String?

    /// When the job was made, for the time limits. The text is always written by `Dates.iso`, so it always reads back.
    public var createdDate: Date { ISO8601DateFormatter().date(from: createdAt) ?? .distantFuture }

    enum CodingKeys: String, CodingKey { case id, machine, workloadId, type, state, params, result, actor, createdAt, finishedAt, step, stepAt }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(machine, forKey: .machine)
        try box.encode(workloadId, forKey: .workloadId)
        try box.encode(type, forKey: .type)
        try box.encode(state, forKey: .state)
        try box.encode(params, forKey: .params)
        try box.encode(result, forKey: .result)
        try box.encode(actor, forKey: .actor)
        try box.encode(createdAt, forKey: .createdAt)
        try box.encode(finishedAt, forKey: .finishedAt)
        try box.encode(step, forKey: .step)
        try box.encode(stepAt, forKey: .stepAt)
    }
}

/// What operators asked machines to do, and how each request ended.
public struct CommandStore {
    private let database: Database
    public static let maxPage = 200

    public init(_ database: Database) { self.database = database }

    public func create(id: String, machine: String, workloadId: String?, type: String, params: [String: String], actor: String, now: Date) throws {
        try database.execute("""
            INSERT INTO commands (id, machine_id, workload_id, type, params_json, state, actor, created_at) VALUES (?, ?, ?, ?, ?, 'queued', ?, ?)
            """, [.text(id), .text(machine), workloadId.map(SQLValue.text) ?? .null, .text(type), .text(try encode(params)), .text(actor), .int(Int(now.timeIntervalSince1970))])
    }

    /// Moves a job on. A job that has already ended stays as it ended (a late answer from a machine cannot undo a timeout), and the first time a job ends the user who
    /// started it gets a notification, in the same transaction. Returns whether the row changed.
    @discardableResult
    public func update(id: String, state: String, result: [String: String]?, now: Date) throws -> Bool {
        try database.transaction {
            guard let before = try get(id), !JobState.isFinal(before.state) else { return false }
            let finished = JobState.isFinal(state)
            try database.execute("UPDATE commands SET state = ?, result_json = ?, finished_at = ? WHERE id = ?",
                                 [.text(state), try result.map { .text(try encode($0)) } ?? .null, finished ? .int(Int(now.timeIntervalSince1970)) : .null, .text(id)])
            guard finished, let after = try get(id) else { return true }
            try NotificationStore(database).add(for: after, now: now)
            return true
        }
    }

    /// Remembers the step a running job reported. Only the fixed names are kept, and only while the job is unfinished; a repeat of the same step keeps its first time.
    public func setStep(id: String, step: String, now: Date) throws {
        guard JobSteps.isKnown(step) else { return }
        try database.execute("UPDATE commands SET step = ?, step_at = ? WHERE id = ? AND state IN ('queued', 'running') AND step IS NOT ?",
                             [.text(step), .int(Int(now.timeIntervalSince1970)), .text(id), .text(step)])
    }

    /// Deletes jobs that ended before `cutoff` (30 days in real use). Returns how many.
    public func pruneFinished(before cutoff: Date) throws -> Int {
        try database.execute("DELETE FROM commands WHERE finished_at IS NOT NULL AND finished_at < ?", [.int(Int(cutoff.timeIntervalSince1970))])
    }

    public func get(_ id: String) throws -> CommandRow? {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at, step, step_at FROM commands WHERE id = ?
            """, [.text(id)]).first.map(row)
    }

    public func recent(limit: Int) throws -> [CommandRow] {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at, step, step_at FROM commands
            ORDER BY created_at DESC, id DESC LIMIT ?
            """, [.int(min(max(limit, 1), Self.maxPage))]).map(row)
    }

    /// The unfinished delete for this VM, if one has already been accepted.
    public func unfinishedDelete(machine: String, workloadId: String) throws -> CommandRow? {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at, step, step_at FROM commands
            WHERE machine_id = ? AND workload_id = ? AND type = 'delete' AND state IN ('queued', 'running')
            ORDER BY created_at DESC, id DESC LIMIT 1
            """, [.text(machine), .text(workloadId)]).first.map(row)
    }

    /// Commands that were still going when the Root last stopped.
    public func unfinished() throws -> [CommandRow] {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at, step, step_at FROM commands
            WHERE state IN ('queued', 'running') ORDER BY created_at
            """).map(row)
    }

    /// The newest chat install or uninstall for one machine (and workload, if any): a failing install is not retried every few seconds, and a removal is not undone.
    public func lastBundleCommand(machine: String, workloadId: String?) throws -> CommandRow? {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at, step, step_at FROM commands
            WHERE machine_id = ? AND type IN ('bundle_install', 'bundle_uninstall') AND COALESCE(workload_id, '') = ? ORDER BY created_at DESC, id DESC LIMIT 1
            """, [.text(machine), .text(workloadId ?? "")]).first.map(row)
    }

    /// The kind of chat command that is still going on this machine (or workload), if one is.
    public func goingBundleCommand(machine: String, workloadId: String?) throws -> BundleCommandKind? {
        guard let last = try lastBundleCommand(machine: machine, workloadId: workloadId), ["queued", "running"].contains(last.state) else { return nil }
        return BundleCommandKind(rawValue: last.type)
    }

    /// True while a create or a delete of a VM is queued or running on the machine. A helper is not replaced then.
    public func hasUnfinishedOrder(machine: String) throws -> Bool {
        let rows = try database.query("SELECT 1 AS found FROM commands WHERE machine_id = ? AND type IN ('create', 'delete') AND state IN ('queued', 'running') LIMIT 1", [.text(machine)])
        return !rows.isEmpty
    }

    /// RAM and disk already promised to creates that have not finished, so two quick requests cannot both take the same room.
    public func promised(machine: String) throws -> (ramMb: Int, diskGb: Int) {
        let rows = try database.query("SELECT params_json FROM commands WHERE machine_id = ? AND type = 'create' AND state IN ('queued', 'running')", [.text(machine)])
        let all = rows.compactMap { try? JSONDecoder().decode([String: String].self, from: Data($0.string("params_json").utf8)) }
        return (all.reduce(0) { $0 + (Int($1["ram_mb"] ?? "") ?? 0) }, all.reduce(0) { $0 + (Int($1["disk_gb"] ?? "") ?? 0) })
    }

    private func row(_ row: Row) -> CommandRow {
        func decode(_ text: String?) -> [String: String]? { text.flatMap { try? JSONDecoder().decode([String: String].self, from: Data($0.utf8)) } }
        return CommandRow(id: row.string("id"), machine: row.string("machine_id"), workloadId: row.optionalString("workload_id"), type: row.string("type"),
                          state: row.string("state"), params: decode(row.string("params_json")) ?? [:], result: decode(row.optionalString("result_json")), actor: row.string("actor"),
                          createdAt: Dates.iso(row.int("created_at")), finishedAt: row.optionalInt("finished_at").map(Dates.iso),
                          step: row.optionalString("step"), stepAt: row.optionalInt("step_at").map(Dates.iso))
    }

    private func encode(_ value: [String: String]) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }
}
