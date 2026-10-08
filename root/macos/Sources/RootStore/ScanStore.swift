import Foundation
import RootCore

public struct ScanResultRow: Encodable, Equatable {
    public let id: Int
    public let ip: String
    public let mac: String?
    public let hostname: String?
    public let vendor: String?
    public let seenBy: [String]
    public let agentPortOpen: Bool
    /// Name of the enrolled machine at this address, if there is one.
    public let machine: String?

    enum CodingKeys: String, CodingKey { case id, ip, mac, hostname, vendor, seenBy, agentPortOpen, machine }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(ip, forKey: .ip)
        try box.encode(mac, forKey: .mac)
        try box.encode(hostname, forKey: .hostname)
        try box.encode(vendor, forKey: .vendor)
        try box.encode(seenBy, forKey: .seenBy)
        try box.encode(agentPortOpen, forKey: .agentPortOpen)
        try box.encode(machine, forKey: .machine)
    }
}

public struct ScanRunSummary: Encodable, Equatable {
    public let id: Int
    public let state: String
    public let subnet: String
    public let sources: [String: String]
    public let startedAt: String
    public let finishedAt: String?
    public let results: [ScanResultRow]

    enum CodingKeys: String, CodingKey { case id, state, subnet, sources, startedAt, finishedAt, results }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(state, forKey: .state)
        try box.encode(subnet, forKey: .subnet)
        try box.encode(sources, forKey: .sources)
        try box.encode(startedAt, forKey: .startedAt)
        try box.encode(finishedAt, forKey: .finishedAt)
        try box.encode(results, forKey: .results)
    }
}

public enum ScanError: Error, Equatable {
    case alreadyRunning
    case notFound
}

/// Scan runs and what each one found. Only the latest runs are kept.
public struct ScanStore {
    private let database: Database
    public static let keepRuns = 20
    public static let staleAfter: TimeInterval = 15 * 60

    public init(_ database: Database) { self.database = database }

    /// Begins a run, or refuses if one is already going. A run that never finished (a crash) stops counting after a while.
    public func start(actor: String, subnet: String, now: Date) throws -> Int {
        try database.transaction {
            let seconds = Int(now.timeIntervalSince1970)
            try database.execute("UPDATE scan_runs SET state = 'failed', finished_at = ? WHERE state = 'running' AND started_at < ?",
                                 [.int(seconds), .int(seconds - Int(Self.staleAfter))])
            guard try database.query("SELECT 1 AS found FROM scan_runs WHERE state = 'running'").isEmpty else { throw ScanError.alreadyRunning }
            try database.execute("INSERT INTO scan_runs (actor, subnet, state, started_at) VALUES (?, ?, 'running', ?)", [.text(actor), .text(subnet), .int(seconds)])
            let id = try database.query("SELECT last_insert_rowid() AS id").first?.int("id") ?? 0
            try database.execute("DELETE FROM scan_runs WHERE id <= ?", [.int(id - Self.keepRuns)])
            return id
        }
    }

    public func finish(runId: Int, findings: [ScanFinding], sources: [String: String], now: Date) throws {
        try database.transaction {
            for item in findings {
                try database.execute("""
                    INSERT OR IGNORE INTO scan_results (run_id, ip, mac, hostname, vendor, seen_by, agent_port_open) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [.int(runId), .text(item.ip), item.mac.map(SQLValue.text) ?? .null, item.hostname.map(SQLValue.text) ?? .null,
                          item.vendor.map(SQLValue.text) ?? .null, .text(item.seenBy.map(\.rawValue).joined(separator: ",")), .int(item.agentPortOpen ? 1 : 0)])
            }
            let json = String(data: try JSONEncoder().encode(sources), encoding: .utf8) ?? "{}"
            try database.execute("UPDATE scan_runs SET state = 'done', sources_json = ?, finished_at = ? WHERE id = ?",
                                 [.text(json), .int(Int(now.timeIntervalSince1970)), .int(runId)])
        }
    }

    public func fail(runId: Int, sources: [String: String], now: Date) throws {
        let json = String(data: try JSONEncoder().encode(sources), encoding: .utf8) ?? "{}"
        try database.execute("UPDATE scan_runs SET state = 'failed', sources_json = ?, finished_at = ? WHERE id = ?",
                             [.text(json), .int(Int(now.timeIntervalSince1970)), .int(runId)])
    }

    public func latest() throws -> ScanRunSummary? {
        guard let id = try database.query("SELECT id FROM scan_runs ORDER BY id DESC LIMIT 1").first?.int("id") else { return nil }
        return try get(id: id)
    }

    public func get(id: Int) throws -> ScanRunSummary {
        guard let run = try database.query("SELECT id, state, subnet, sources_json, started_at, finished_at FROM scan_runs WHERE id = ?", [.int(id)]).first else {
            throw ScanError.notFound
        }
        let rows = try database.query("""
            SELECT r.id, r.ip, r.mac, r.hostname, r.vendor, r.seen_by, r.agent_port_open, m.name AS machine
            FROM scan_results r LEFT JOIN machines m ON m.ip = r.ip WHERE r.run_id = ? ORDER BY r.id
            """, [.int(id)]).map(Self.resultRow)
        return ScanRunSummary(id: run.int("id"), state: run.string("state"), subnet: run.string("subnet"),
                              sources: (try? JSONDecoder().decode([String: String].self, from: Data(run.string("sources_json").utf8))) ?? [:],
                              startedAt: Dates.iso(run.int("started_at")), finishedAt: run.optionalInt("finished_at").map(Dates.iso),
                              results: rows.sorted { (Subnet.address($0.ip) ?? 0) < (Subnet.address($1.ip) ?? 0) })
    }

    /// One result of one run, for the add step.
    public func result(runId: Int, resultId: Int) throws -> ScanResultRow {
        guard let row = try get(id: runId).results.first(where: { $0.id == resultId }) else { throw ScanError.notFound }
        return row
    }

    private static func resultRow(_ row: Row) -> ScanResultRow {
        ScanResultRow(id: row.int("id"), ip: row.string("ip"), mac: row.optionalString("mac"), hostname: row.optionalString("hostname"),
                      vendor: row.optionalString("vendor"), seenBy: row.string("seen_by").split(separator: ",").map(String.init),
                      agentPortOpen: row.int("agent_port_open") == 1, machine: row.optionalString("machine"))
    }
}
