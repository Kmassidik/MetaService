import Foundation

/// The audit rows written for AI tokens: every actor starts with `mcp:`. The audit log itself is append only; this only reads it.
public struct McpActivityStore {
    private let database: Database
    public static let maxPage = 200

    public init(_ database: Database) { self.database = database }

    /// Newest first.
    public func recent(limit: Int) throws -> [AuditEntry] {
        try database.query("SELECT id, ts, actor, action, target, detail FROM audit_log WHERE actor LIKE 'mcp:%' ORDER BY id DESC LIMIT ?",
                           [.int(min(max(limit, 1), Self.maxPage))]).map {
            AuditEntry(id: $0.int("id"), ts: Dates.iso($0.int("ts")), actor: $0.string("actor"), action: $0.string("action"),
                       target: $0.optionalString("target"), detail: $0.string("detail"))
        }
    }
}
