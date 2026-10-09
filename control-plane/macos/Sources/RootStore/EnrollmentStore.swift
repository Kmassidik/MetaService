import Foundation
import RootCore

public enum EnrollmentError: Error, Equatable {
    case machineExists
}

/// One-time enrollment tokens. Only the hash is stored; the token is shown once.
public struct EnrollmentStore {
    private let database: Database
    public static let lifetime: TimeInterval = 15 * 60

    public init(_ database: Database) { self.database = database }

    public func create(machineName: String, expectedIp: String? = nil, now: Date) throws -> (token: String, expires: Date) {
        let existing = try database.query("SELECT 1 AS found FROM machines WHERE name = ?", [.text(machineName)])
        guard existing.isEmpty else { throw EnrollmentError.machineExists }
        let token = Tokens.random()
        let expires = now.addingTimeInterval(Self.lifetime)
        try database.execute("INSERT INTO enrollments (token_hash, machine_name, created_at, expires_at, expected_ip) VALUES (?, ?, ?, ?, ?)",
                             [.text(Tokens.sha256Hex(token)), .text(machineName), .int(Int(now.timeIntervalSince1970)), .int(Int(expires.timeIntervalSince1970)),
                              expectedIp.map(SQLValue.text) ?? .null])
        return (token, expires)
    }

    /// Uses the token up. True only the first time, only for the right machine name, only before it expires, and, when the
    /// token was pinned to an address, only from that address.
    public func consume(token: String, machineName: String, fromIp: String? = nil, now: Date) throws -> Bool {
        let changed = try database.execute("""
            UPDATE enrollments SET used_at = ?
            WHERE token_hash = ? AND machine_name = ? AND used_at IS NULL AND expires_at > ? AND (expected_ip IS NULL OR expected_ip = ?)
            """, [.int(Int(now.timeIntervalSince1970)), .text(Tokens.sha256Hex(token)), .text(machineName), .int(Int(now.timeIntervalSince1970)),
                  fromIp.map(SQLValue.text) ?? .null])
        return changed == 1
    }
}
