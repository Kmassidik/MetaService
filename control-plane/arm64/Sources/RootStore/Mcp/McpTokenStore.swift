import Foundation
import RootCore

/// One API token as stored. The token text is not here and never was: only its hash is kept, and the hash is not here either.
public struct McpTokenRecord: Equatable {
    public let id: String
    public let name: String
    public let prefix: String
    public let scopes: Set<McpScope>
    public let quotas: McpQuotas
    public let autoApprove: Bool
    public let createdBy: String
    public let createdAt: Date
    public let expiresAt: Date
    public let lastUsedAt: Date?
    public let revokedAt: Date?

    /// Why this token cannot be used right now, in a word: `revoked`, `expired`, or nil when it works.
    public func refusal(at now: Date) -> String? {
        if revokedAt != nil { return "revoked" }
        return expiresAt <= now ? "expired" : nil
    }

    /// The actor name every audit row and command of this token carries.
    public var actor: String { "mcp:\(name)" }
}

/// What a new token is made from. `tokenHash` is the SHA-256 of the text; the text itself is not a parameter, so this store can never write it.
public struct NewMcpToken {
    public let id: String
    public let name: String
    public let prefix: String
    public let tokenHash: String
    public let scopes: Set<McpScope>
    public let quotas: McpQuotas
    public let autoApprove: Bool
    public let createdBy: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: String, name: String, prefix: String, tokenHash: String, scopes: Set<McpScope>, quotas: McpQuotas, autoApprove: Bool, createdBy: String, createdAt: Date, expiresAt: Date) {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.tokenHash = tokenHash
        self.scopes = scopes
        self.quotas = quotas
        self.autoApprove = autoApprove
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// The API tokens of AI clients (mcp/SPEC.md section 3). Looked up by the hash of the text they present.
public struct McpTokenStore {
    private let database: Database
    /// `last_used_at` moves at most this often, so a busy client does not write on every call.
    public static let lastUsedStepSeconds = 60

    public init(_ database: Database) { self.database = database }

    public func create(_ token: NewMcpToken) throws {
        let scopes = String(decoding: try JSONSerialization.data(withJSONObject: McpScope.names(token.scopes)), as: UTF8.self)
        let quotas = String(decoding: try JSONSerialization.data(withJSONObject: token.quotas.json, options: [.sortedKeys]), as: UTF8.self)
        try database.execute("""
            INSERT INTO api_tokens (id, name, prefix, token_hash, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(token.id), .text(token.name), .text(token.prefix), .text(token.tokenHash), .text(scopes), .text(quotas), .int(token.autoApprove ? 1 : 0),
                  .text(token.createdBy), .int(Self.seconds(token.createdAt)), .int(Self.seconds(token.expiresAt))])
    }

    /// The token whose text hashes to this, whatever its state, so a revoked or expired one can be told from an unknown one.
    public func find(hash: String) throws -> McpTokenRecord? {
        try database.query("SELECT id, name, prefix, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at, last_used_at, revoked_at FROM api_tokens WHERE token_hash = ?",
                           [.text(hash)]).first.map(Self.record)
    }

    public func get(id: String) throws -> McpTokenRecord? {
        try database.query("SELECT id, name, prefix, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at, last_used_at, revoked_at FROM api_tokens WHERE id = ?",
                           [.text(id)]).first.map(Self.record)
    }

    /// Newest first, revoked ones included, so the panel can show what was revoked.
    public func list() throws -> [McpTokenRecord] {
        try database.query("SELECT id, name, prefix, scopes_json, quotas_json, auto_approve, created_by, created_at, expires_at, last_used_at, revoked_at FROM api_tokens ORDER BY created_at DESC, rowid DESC")
            .map(Self.record)
    }

    /// True when a token that is not revoked already has this name (names show up in the audit trail, so two live tokens must not share one).
    public func liveNameExists(_ name: String) throws -> Bool {
        try !database.query("SELECT 1 AS found FROM api_tokens WHERE name = ? AND revoked_at IS NULL", [.text(name)]).isEmpty
    }

    /// False when there is no such token or it was already revoked, so a second click changes nothing.
    @discardableResult
    public func revoke(id: String, now: Date) throws -> Bool {
        try database.execute("UPDATE api_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL", [.int(Self.seconds(now)), .text(id)]) > 0
    }

    public func touch(id: String, now: Date) throws {
        try database.execute("UPDATE api_tokens SET last_used_at = ? WHERE id = ? AND (last_used_at IS NULL OR last_used_at <= ?)",
                             [.int(Self.seconds(now)), .text(id), .int(Self.seconds(now) - Self.lastUsedStepSeconds)])
    }

    static func seconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    private static func record(_ row: Row) -> McpTokenRecord {
        let names = (try? JSONSerialization.jsonObject(with: Data(row.string("scopes_json").utf8))) as? [String] ?? []
        return McpTokenRecord(id: row.string("id"), name: row.string("name"), prefix: row.string("prefix"),
                              scopes: Set(names.compactMap(McpScope.init(rawValue:))), quotas: McpQuotas(stored: row.string("quotas_json")),
                              autoApprove: row.int("auto_approve") == 1, createdBy: row.string("created_by"),
                              createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))), expiresAt: Date(timeIntervalSince1970: TimeInterval(row.int("expires_at"))),
                              lastUsedAt: row.optionalInt("last_used_at").map { Date(timeIntervalSince1970: TimeInterval($0)) },
                              revokedAt: row.optionalInt("revoked_at").map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}
