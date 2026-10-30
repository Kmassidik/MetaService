import Foundation

public enum McpRequestKind: String, Equatable {
    case create, delete, start, stop
}

/// Where a request stands: `running` has a command on a machine (or is about to), `done` and `failed` are final.
public enum McpRequestState: String, Equatable {
    case running, done, failed
}

public struct McpRequestRow: Equatable {
    public let id: String
    public let personId: String
    public let tokenId: String
    public let kind: McpRequestKind
    /// What was asked, as JSON: machine, vm, size and so on, and a public key until the VM has it. Nothing else that could hold a secret.
    public let params: [String: Any]
    public let state: McpRequestState
    public let commandId: String?
    public let result: [String: Any]?
    public let idempotencyKey: String?
    public let createdAt: Date

    public static func == (left: McpRequestRow, right: McpRequestRow) -> Bool {
        left.id == right.id && left.state == right.state && left.commandId == right.commandId
    }
}

public struct NewMcpRequest {
    public let id: String
    public let personId: String
    public let tokenId: String
    public let kind: McpRequestKind
    public let params: [String: Any]
    public let idempotencyKey: String?
    public let createdAt: Date

    public init(id: String, personId: String, tokenId: String, kind: McpRequestKind, params: [String: Any], idempotencyKey: String?, createdAt: Date) {
        self.id = id
        self.personId = personId
        self.tokenId = tokenId
        self.kind = kind
        self.params = params
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
    }
}

/// The creates, starts, stops and deletes a person asked for, kept so a slow one can be followed with `get_request` and a repeated idempotency key gives the first answer.
public struct McpRequestStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    /// Stores a request. With an idempotency key already used by this person, nothing is written and the earlier request comes back (`created` false).
    public func create(_ item: NewMcpRequest) throws -> (request: McpRequestRow, created: Bool) {
        try database.transaction {
            if let key = item.idempotencyKey, let existing = try find(person: item.personId, idempotencyKey: key) { return (existing, false) }
            try database.execute("""
                INSERT INTO mcp_requests (id, person_id, token_id, kind, params_json, state, idempotency_key, created_at) VALUES (?, ?, ?, ?, ?, 'running', ?, ?)
                """, [.text(item.id), .text(item.personId), .text(item.tokenId), .text(item.kind.rawValue), .text(Self.encode(item.params)),
                      item.idempotencyKey.map(SQLValue.text) ?? .null, .int(McpTokenStore.seconds(item.createdAt))])
            guard let stored = try get(id: item.id) else { throw DatabaseError(code: 1, message: "request not stored") }
            return (stored, true)
        }
    }

    public func get(id: String) throws -> McpRequestRow? {
        try database.query("SELECT id, person_id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at FROM mcp_requests WHERE id = ?",
                           [.text(id)]).first.flatMap(Self.row)
    }

    public func find(person: String, idempotencyKey: String) throws -> McpRequestRow? {
        try database.query("SELECT id, person_id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at FROM mcp_requests WHERE person_id = ? AND idempotency_key = ?",
                           [.text(person), .text(idempotencyKey)]).first.flatMap(Self.row)
    }

    /// Requests of one person that are still going.
    public func unfinished(person: String) throws -> [McpRequestRow] {
        try database.query("SELECT id, person_id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at FROM mcp_requests WHERE person_id = ? AND state = 'running' ORDER BY created_at, rowid",
                           [.text(person)]).compactMap(Self.row)
    }

    /// Creates of one person that still hold the public key they were asked to give the VM.
    public func withPublicKey(person: String) throws -> [McpRequestRow] {
        try database.query("SELECT id, person_id, token_id, kind, params_json, state, command_id, result_json, idempotency_key, created_at FROM mcp_requests WHERE person_id = ? AND kind = 'create' AND state IN ('running', 'done') AND params_json LIKE '%ssh_public_key%'",
                           [.text(person)]).compactMap(Self.row)
    }

    /// Replaces the stored action, for instance after a public key was handed to the VM and no longer needs to be kept.
    public func setParams(id: String, params: [String: Any]) throws {
        try database.execute("UPDATE mcp_requests SET params_json = ? WHERE id = ?", [.text(Self.encode(params)), .text(id)])
    }

    public func setCommand(id: String, command: String) throws {
        try database.execute("UPDATE mcp_requests SET command_id = ? WHERE id = ?", [.text(command), .text(id)])
    }

    /// Ends a request once: a request that is already done or failed keeps its answer.
    public func finish(id: String, state: McpRequestState, result: [String: Any]) throws {
        try database.execute("UPDATE mcp_requests SET state = ?, result_json = ? WHERE id = ? AND state = 'running'", [.text(state.rawValue), .text(Self.encode(result)), .text(id)])
    }

    static func encode(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }

    private static func row(_ row: Row) -> McpRequestRow? {
        guard let kind = McpRequestKind(rawValue: row.string("kind")), let state = McpRequestState(rawValue: row.string("state")) else { return nil }
        func object(_ text: String?) -> [String: Any]? { text.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } }
        return McpRequestRow(id: row.string("id"), personId: row.string("person_id"), tokenId: row.string("token_id"), kind: kind, params: object(row.string("params_json")) ?? [:], state: state,
                             commandId: row.optionalString("command_id"), result: object(row.optionalString("result_json")), idempotencyKey: row.optionalString("idempotency_key"),
                             createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))))
    }
}
