import Foundation
import RootCore

public struct SessionRecord: Equatable {
    public let username: String
    public let csrfToken: String
}

/// Operator sessions. The cookie value is random; only its hash is stored.
public struct SessionStore {
    private let database: Database
    public static let lifetime: TimeInterval = 12 * 3600

    public init(_ database: Database) { self.database = database }

    public func create(username: String, now: Date) throws -> (token: String, csrf: String) {
        let token = Tokens.random(), csrf = Tokens.random()
        try database.execute("DELETE FROM sessions WHERE expires_at <= ?", [.int(Int(now.timeIntervalSince1970))])
        try database.execute("INSERT INTO sessions (token_hash, username, csrf_token, created_at, expires_at) VALUES (?, ?, ?, ?, ?)",
                             [.text(Tokens.sha256Hex(token)), .text(username), .text(csrf), .int(Int(now.timeIntervalSince1970)),
                              .int(Int(now.addingTimeInterval(Self.lifetime).timeIntervalSince1970))])
        return (token, csrf)
    }

    public func lookup(token: String, now: Date) throws -> SessionRecord? {
        let rows = try database.query("SELECT username, csrf_token FROM sessions WHERE token_hash = ? AND expires_at > ?",
                                      [.text(Tokens.sha256Hex(token)), .int(Int(now.timeIntervalSince1970))])
        return rows.first.map { SessionRecord(username: $0.string("username"), csrfToken: $0.string("csrf_token")) }
    }

    public func delete(token: String) throws {
        try database.execute("DELETE FROM sessions WHERE token_hash = ?", [.text(Tokens.sha256Hex(token))])
    }
}
