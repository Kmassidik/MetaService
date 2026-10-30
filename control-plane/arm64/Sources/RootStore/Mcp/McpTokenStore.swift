import Foundation
import RootCore

/// One API token as stored. The token text is not here and never was: only its hash is kept, and the hash is not here either.
/// A token belongs to one person; the quotas and the VMs are the person's.
public struct McpTokenRecord: Equatable {
    public let id: String
    public let name: String
    public let prefix: String
    public let personId: String
    public let scopes: Set<McpScope>
    public let createdBy: String
    public let createdAt: Date
    public let expiresAt: Date
    public let lastUsedAt: Date?
    public let revokedAt: Date?
    /// What the client called itself the last time it said hello (MCP `initialize`); nil before that.
    public let clientName: String?
    public let clientVersion: String?

    /// Why this token cannot be used right now, in a word: `revoked`, `expired`, or nil when it works.
    public func refusal(at now: Date) -> String? {
        if revokedAt != nil { return "revoked" }
        return expiresAt <= now ? "expired" : nil
    }
}

/// What a new token is made from. `tokenHash` is the SHA-256 of the text; the text itself is not a parameter, so this store can never write it.
public struct NewMcpToken {
    public let id: String
    public let name: String
    public let prefix: String
    public let personId: String
    public let tokenHash: String
    public let scopes: Set<McpScope>
    public let createdBy: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: String, name: String, prefix: String, personId: String, tokenHash: String, scopes: Set<McpScope>, createdBy: String, createdAt: Date, expiresAt: Date) {
        self.id = id
        self.name = name
        self.prefix = prefix
        self.personId = personId
        self.tokenHash = tokenHash
        self.scopes = scopes
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
        try database.execute("""
            INSERT INTO api_tokens (id, name, prefix, person_id, token_hash, scopes_json, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(token.id), .text(token.name), .text(token.prefix), .text(token.personId), .text(token.tokenHash), .text(scopes), .text(token.createdBy),
                  .int(Self.seconds(token.createdAt)), .int(Self.seconds(token.expiresAt))])
    }

    /// The token whose text hashes to this, whatever its state, so a revoked or expired one can be told from an unknown one.
    public func find(hash: String) throws -> McpTokenRecord? {
        try database.query("SELECT id, name, prefix, person_id, scopes_json, created_by, created_at, expires_at, last_used_at, revoked_at, client_name, client_version FROM api_tokens WHERE token_hash = ?",
                           [.text(hash)]).first.map(Self.record)
    }

    public func get(id: String) throws -> McpTokenRecord? {
        try database.query("SELECT id, name, prefix, person_id, scopes_json, created_by, created_at, expires_at, last_used_at, revoked_at, client_name, client_version FROM api_tokens WHERE id = ?",
                           [.text(id)]).first.map(Self.record)
    }

    /// Newest first, revoked ones included, so the panel can show what was revoked.
    public func list() throws -> [McpTokenRecord] {
        try database.query("SELECT id, name, prefix, person_id, scopes_json, created_by, created_at, expires_at, last_used_at, revoked_at, client_name, client_version FROM api_tokens ORDER BY created_at DESC, rowid DESC")
            .map(Self.record)
    }

    /// False when there is no such token or it was already revoked, so a second click changes nothing.
    @discardableResult
    public func revoke(id: String, now: Date) throws -> Bool {
        try database.execute("UPDATE api_tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL", [.int(Self.seconds(now)), .text(id)]) > 0
    }

    /// Remembers what the client said about itself at `initialize`, to put on the creator record of the VMs it makes.
    public func setClient(id: String, name: String?, version: String?) throws {
        try database.execute("UPDATE api_tokens SET client_name = ?, client_version = ? WHERE id = ?", [name.map(SQLValue.text) ?? .null, version.map(SQLValue.text) ?? .null, .text(id)])
    }

    /// How many tokens a person has that still work (not revoked).
    public func liveCount(person: String) throws -> Int {
        try database.query("SELECT COUNT(*) AS n FROM api_tokens WHERE person_id = ? AND revoked_at IS NULL", [.text(person)]).first?.int("n") ?? 0
    }

    /// The latest use of any token of the person.
    public func lastUsed(person: String) throws -> Date? {
        try database.query("SELECT MAX(last_used_at) AS at FROM api_tokens WHERE person_id = ?", [.text(person)]).first?.optionalInt("at").map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public func touch(id: String, now: Date) throws {
        try database.execute("UPDATE api_tokens SET last_used_at = ? WHERE id = ? AND (last_used_at IS NULL OR last_used_at <= ?)",
                             [.int(Self.seconds(now)), .text(id), .int(Self.seconds(now) - Self.lastUsedStepSeconds)])
    }

    static func seconds(_ date: Date) -> Int { Int(date.timeIntervalSince1970) }

    private static func record(_ row: Row) -> McpTokenRecord {
        let names = (try? JSONSerialization.jsonObject(with: Data(row.string("scopes_json").utf8))) as? [String] ?? []
        return McpTokenRecord(id: row.string("id"), name: row.string("name"), prefix: row.string("prefix"), personId: row.string("person_id"),
                              scopes: Set(names.compactMap(McpScope.init(rawValue:))), createdBy: row.string("created_by"),
                              createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))), expiresAt: Date(timeIntervalSince1970: TimeInterval(row.int("expires_at"))),
                              lastUsedAt: row.optionalInt("last_used_at").map { Date(timeIntervalSince1970: TimeInterval($0)) },
                              revokedAt: row.optionalInt("revoked_at").map { Date(timeIntervalSince1970: TimeInterval($0)) },
                              clientName: row.optionalString("client_name"), clientVersion: row.optionalString("client_version"))
    }
}
