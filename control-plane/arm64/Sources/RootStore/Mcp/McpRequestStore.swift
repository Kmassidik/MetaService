import Foundation
import RootCore

public enum McpRequestKind: String, Equatable {
    case create, delete, start, stop
}

/// Where a request stands. `pendingApproval` waits for a person; `approved` is a yes not yet carried out; `running` has a command on a machine;
/// `done` and `failed` are final, and so are `denied` and `expired`.
public enum McpRequestState: String, Equatable {
    case pendingApproval = "pending_approval"
    case approved, denied, running, done, failed, expired
}

public struct McpRequestRow: Equatable {
    public let id: String
    public let tokenId: String
    public let kind: McpRequestKind
    /// The stored action as JSON: what the AI asked for, and nothing that could hold a key or a token.
    public let params: [String: Any]
    public let state: McpRequestState
    public let commandId: String?
    public let result: [String: Any]?
    public let idempotencyKey: String?
    public let createdAt: Date
    public let decidedBy: String?
    public let decidedAt: Date?
    public let expiresAt: Date

    public static func == (left: McpRequestRow, right: McpRequestRow) -> Bool {
        left.id == right.id && left.state == right.state && left.commandId == right.commandId
    }
}

public struct NewMcpRequest {
    public let id: String
    public let tokenId: String
    public let kind: McpRequestKind
    public let params: [String: Any]
    public let state: McpRequestState
    public let idempotencyKey: String?
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: String, tokenId: String, kind: McpRequestKind, params: [String: Any], state: McpRequestState, idempotencyKey: String?, createdAt: Date, expiresAt: Date) {
        self.id = id
        self.tokenId = tokenId
        self.kind = kind
        self.params = params
        self.state = state
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// Every create, start, stop and delete a token asked for, and the yes or no a person gave (mcp/SPEC.md sections 5 and 6).
public struct McpRequestStore {
    private let database: Database
    /// A request waits this long for a person.
    public static let approvalSeconds = 24 * 3600
    public static let maxList = 200

    public init(_ database: Database) { self.database = database }

    /// Stores a request. With an idempotency key already used by this token, nothing is written and the earlier request comes back (`created` false).
    public func create(_ item: NewMcpRequest) throws -> (request: McpRequestRow, created: Bool) {
        try database.transaction {
            if let key = item.idempotencyKey, let existing = try find(token: item.tokenId, idempotencyKey: key) { return (existing, false) }
            try database.execute("""
                INSERT INTO mcp_requests (id, token_id, kind, params_json, state, idempotency_key, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(item.id), .text(item.tokenId), .text(item.kind.rawValue), .text(Self.encode(item.params)), .text(item.state.rawValue),
                      item.idempotencyKey.map(SQLValue.text) ?? .null, .int(McpTokenStore.seconds(item.createdAt)), .int(McpTokenStore.seconds(item.expiresAt))])
            guard let stored = try get(id: item.id) else { throw DatabaseError(code: 1, message: "request not stored") }
            return (stored, true)
        }
    }

    public func get(id: String) throws -> McpRequestRow? {
        try database.query("SELECT id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at, decided_by, decided_at, expires_at FROM mcp_requests WHERE id = ?",
                           [.text(id)]).first.flatMap(Self.row)
    }

    public func find(token: String, idempotencyKey: String) throws -> McpRequestRow? {
        try database.query("SELECT id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at, decided_by, decided_at, expires_at FROM mcp_requests WHERE token_id = ? AND idempotency_key = ?",
                           [.text(token), .text(idempotencyKey)]).first.flatMap(Self.row)
    }

    /// The requests waiting for a person, oldest first.
    public func pending() throws -> [McpRequestRow] {
        try database.query("SELECT id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at, decided_by, decided_at, expires_at FROM mcp_requests WHERE state = 'pending_approval' ORDER BY created_at, rowid")
            .compactMap(Self.row)
    }

    /// The ones a person already decided on or that ended, newest first.
    public func recent(limit: Int) throws -> [McpRequestRow] {
        try database.query("SELECT id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at, decided_by, decided_at, expires_at FROM mcp_requests WHERE state != 'pending_approval' ORDER BY created_at DESC, rowid DESC LIMIT ?",
                           [.int(min(max(limit, 1), Self.maxList))]).compactMap(Self.row)
    }

    /// Requests of one token that still change: not yet done, failed, denied or expired.
    public func unfinished(token: String) throws -> [McpRequestRow] {
        try database.query("SELECT id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at, decided_by, decided_at, expires_at FROM mcp_requests WHERE token_id = ? AND state IN ('approved', 'running') ORDER BY created_at, rowid",
                           [.text(token)]).compactMap(Self.row)
    }

    /// A person's yes or no. Works only on a request still waiting, so two operators pressing at once decide it once. True when this call decided it.
    @discardableResult
    public func decide(id: String, to state: McpRequestState, by operatorName: String, now: Date) throws -> Bool {
        try database.execute("UPDATE mcp_requests SET state = ?, decided_by = ?, decided_at = ? WHERE id = ? AND state = 'pending_approval'",
                             [.text(state.rawValue), .text(operatorName), .int(McpTokenStore.seconds(now)), .text(id)]) > 0
    }

    /// Moves a request on from the state it is expected to be in. True when this call moved it.
    @discardableResult
    public func move(id: String, from: McpRequestState, to: McpRequestState) throws -> Bool {
        try database.execute("UPDATE mcp_requests SET state = ? WHERE id = ? AND state = ?", [.text(to.rawValue), .text(id), .text(from.rawValue)]) > 0
    }

    public func setCommand(id: String, command: String) throws {
        try database.execute("UPDATE mcp_requests SET command_id = ? WHERE id = ?", [.text(command), .text(id)])
    }

    public func finish(id: String, state: McpRequestState, result: [String: Any]) throws {
        try database.execute("UPDATE mcp_requests SET state = ?, result_json = ? WHERE id = ? AND state NOT IN ('done', 'failed', 'denied', 'expired')",
                             [.text(state.rawValue), .text(Self.encode(result)), .text(id)])
    }

    /// Pending requests older than their expiry become `expired`. Returns how many.
    @discardableResult
    public func expireOld(now: Date) throws -> Int {
        try database.execute("UPDATE mcp_requests SET state = 'expired' WHERE state = 'pending_approval' AND expires_at <= ?", [.int(McpTokenStore.seconds(now))])
    }

    static func encode(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }

    private static func row(_ row: Row) -> McpRequestRow? {
        guard let kind = McpRequestKind(rawValue: row.string("kind")), let state = McpRequestState(rawValue: row.string("state")) else { return nil }
        func object(_ text: String?) -> [String: Any]? { text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } }
        return McpRequestRow(id: row.string("id"), tokenId: row.string("token_id"), kind: kind, params: object(row.string("params_json")) ?? [:], state: state,
                             commandId: row.optionalString("command_id"), result: object(row.optionalString("result_json")), idempotencyKey: row.optionalString("idempotency_key"),
                             createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))), decidedBy: row.optionalString("decided_by"),
                             decidedAt: row.optionalInt("decided_at").map { Date(timeIntervalSince1970: TimeInterval($0)) }, expiresAt: Date(timeIntervalSince1970: TimeInterval(row.int("expires_at"))))
    }
}
