import Foundation

public struct AuditEntry: Encodable, Equatable {
    public let id: Int
    public let ts: String
    public let actor: String
    public let action: String
    public let target: String?
    public let detail: String

    enum CodingKeys: String, CodingKey { case id, ts, actor, action, target, detail }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(ts, forKey: .ts)
        try box.encode(actor, forKey: .actor)
        try box.encode(action, forKey: .action)
        try box.encode(target, forKey: .target)
        try box.encode(detail, forKey: .detail)
    }
}

/// Append-only history of every action. The database itself refuses updates and deletes.
public struct AuditStore {
    private let database: Database
    public static let maxPage = 200

    public init(_ database: Database) { self.database = database }

    public func record(actor: String, action: String, target: String? = nil, detail: [String: String] = [:], at date: Date) throws {
        let json = String(data: try JSONEncoder().encode(detail), encoding: .utf8) ?? "{}"
        try database.execute("INSERT INTO audit_log (ts, actor, action, target, detail) VALUES (?, ?, ?, ?, ?)",
                             [.int(Int(date.timeIntervalSince1970)), .text(actor), .text(action),
                              target.map(SQLValue.text) ?? .null, .text(json)])
    }

    /// Newest first. `before` is an entry id: only older entries are returned.
    public func list(limit: Int, before: Int?) throws -> [AuditEntry] {
        let size = min(max(limit, 1), Self.maxPage)
        let rows = try database.query("SELECT id, ts, actor, action, target, detail FROM audit_log WHERE id < ? ORDER BY id DESC LIMIT ?",
                                      [.int(before ?? Int.max), .int(size)])
        return rows.map {
            AuditEntry(id: $0.int("id"), ts: Dates.iso($0.int("ts")), actor: $0.string("actor"), action: $0.string("action"),
                       target: $0.optionalString("target"), detail: $0.string("detail"))
        }
    }
}

enum Dates {
    static func iso(_ seconds: Int) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
