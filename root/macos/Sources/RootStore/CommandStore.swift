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

    enum CodingKeys: String, CodingKey { case id, machine, workloadId, type, state, params, result, actor, createdAt, finishedAt }

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

    public func update(id: String, state: String, result: [String: String]?, now: Date) throws {
        let finished = ["succeeded", "failed"].contains(state)
        try database.execute("UPDATE commands SET state = ?, result_json = ?, finished_at = ? WHERE id = ?",
                             [.text(state), try result.map { .text(try encode($0)) } ?? .null, finished ? .int(Int(now.timeIntervalSince1970)) : .null, .text(id)])
    }

    public func get(_ id: String) throws -> CommandRow? {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at FROM commands WHERE id = ?
            """, [.text(id)]).first.map(row)
    }

    public func recent(limit: Int) throws -> [CommandRow] {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at FROM commands
            ORDER BY created_at DESC, id DESC LIMIT ?
            """, [.int(min(max(limit, 1), Self.maxPage))]).map(row)
    }

    /// Commands that were still going when the Root last stopped.
    public func unfinished() throws -> [CommandRow] {
        try database.query("""
            SELECT id, machine_id, workload_id, type, params_json, state, result_json, actor, created_at, finished_at FROM commands
            WHERE state IN ('queued', 'running') ORDER BY created_at
            """).map(row)
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
                          createdAt: Dates.iso(row.int("created_at")), finishedAt: row.optionalInt("finished_at").map(Dates.iso))
    }

    private func encode(_ value: [String: String]) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }
}
