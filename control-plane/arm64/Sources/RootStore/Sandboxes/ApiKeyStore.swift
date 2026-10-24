import Foundation
import RootCore

/// The API keys of the sandbox teams. Only a prefix for display and the SHA-256 of the secret are kept; the key text
/// itself is never written, never returned and never logged after the moment it is made (see sandbox/README.md,
/// "Teams, keys and limits").
public struct ApiKeyStore {
    private let database: Database
    /// The most rows one list answers with. The panel asks for every key it shows in one go.
    public static let maxList = 500

    public init(_ database: Database) { self.database = database }

    /// Stores a key from the parts a new key is kept as. The key text is not a parameter on purpose, so this store can
    /// never write it. A duplicate prefix throws the database's constraint error.
    public func create(id: String, team: String, prefix: String, secretHash: String, now: Date) throws {
        try database.execute("INSERT INTO api_keys (id, team, prefix, secret_hash, created_at) VALUES (?, ?, ?, ?, ?)",
                             [.text(id), .text(team), .text(prefix), .text(secretHash), .int(Int(now.timeIntervalSince1970))])
    }

    /// The key with this prefix, revoked or not, so a revoked key can be told from an unknown one. Nil when none.
    public func find(prefix: String) throws -> StoredApiKey? {
        try database.query("SELECT id, team, prefix, secret_hash, revoked_at FROM api_keys WHERE prefix = ?", [.text(prefix)]).first.map {
            StoredApiKey(id: $0.string("id"), team: $0.string("team"), prefix: $0.string("prefix"), secretHash: $0.string("secret_hash"),
                         revokedAt: $0.optionalInt("revoked_at").map { Date(timeIntervalSince1970: TimeInterval($0)) })
        }
    }

    /// Checks a presented key and notes the use when it is good. Throws `ApiKeyRefusal` (unknown or revoked) otherwise.
    /// The text is used for the check and dropped; it is not stored.
    public func authenticate(_ text: String, now: Date) throws -> StoredApiKey {
        try database.transaction {
            guard let parts = ApiKeyRules.parse(text) else { throw ApiKeyRefusal.unknown }
            guard let stored = try find(prefix: parts.prefix) else { throw ApiKeyRefusal.unknown }
            switch ApiKeyGate.check(parts: parts, against: stored) {
            case .accepted(let key):
                try database.execute("UPDATE api_keys SET last_used_at = ? WHERE id = ?",
                                     [.int(Int(now.timeIntervalSince1970)), .text(key.id)])
                return key
            case .revoked:
                throw ApiKeyRefusal.revoked
            case .unknown:
                throw ApiKeyRefusal.unknown
            }
        }
    }

    /// Revokes a live key of the team. False when there is no such key, or it was already revoked, so a second click is
    /// harmless and writes no second audit entry.
    @discardableResult
    public func revoke(id: String, team: String, now: Date) throws -> Bool {
        try database.execute("UPDATE api_keys SET revoked_at = ? WHERE id = ? AND team = ? AND revoked_at IS NULL",
                             [.int(Int(now.timeIntervalSince1970)), .text(id), .text(team)]) > 0
    }

    /// Every key of a team, oldest first. Never the hash.
    public func list(team: String) throws -> [ApiKeyRecord] {
        try database.query("SELECT id, team, prefix, created_at, last_used_at, revoked_at FROM api_keys WHERE team = ? ORDER BY created_at, rowid",
                           [.text(team)]).map(Self.record)
    }

    /// Every key of every team, newest first: the panel's list, which names the team next to each key. Never the hash.
    public func listAll(limit: Int = ApiKeyStore.maxList) throws -> [ApiKeyRecord] {
        let size = min(max(limit, 1), Self.maxList)
        return try database.query("SELECT id, team, prefix, created_at, last_used_at, revoked_at FROM api_keys ORDER BY created_at DESC, rowid DESC LIMIT ?",
                                  [.int(size)]).map(Self.record)
    }

    /// One key by its row id, revoked or not. The panel needs it to tell "no such key" from "already revoked", and to name
    /// the key's team before revoking it.
    public func get(id: String) throws -> ApiKeyRecord? {
        try database.query("SELECT id, team, prefix, created_at, last_used_at, revoked_at FROM api_keys WHERE id = ?",
                           [.text(id)]).first.map(Self.record)
    }

    private static func record(_ row: Row) -> ApiKeyRecord {
        ApiKeyRecord(id: row.string("id"), team: row.string("team"), prefix: row.string("prefix"),
                     createdAt: Date(timeIntervalSince1970: TimeInterval(row.int("created_at"))),
                     lastUsedAt: row.optionalInt("last_used_at").map { Date(timeIntervalSince1970: TimeInterval($0)) },
                     revokedAt: row.optionalInt("revoked_at").map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}
