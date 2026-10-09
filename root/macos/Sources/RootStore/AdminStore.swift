import Foundation
import RootCore

public struct AdminRecord: Equatable {
    public let username: String
    public let salt: Data
    public let hash: Data
    public let iterations: Int
}

/// The one operator account, created on first run. Only a salted hash of the password is kept.
public struct AdminStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public var isConfigured: Bool { ((try? get()) ?? nil) != nil }

    public func get() throws -> AdminRecord? {
        try database.query("SELECT username, salt, hash, iterations FROM admin WHERE id = 1").first.flatMap { row in
            guard let salt = Data(base64Encoded: row.string("salt")), let hash = Data(base64Encoded: row.string("hash")) else { return nil }
            return AdminRecord(username: row.string("username"), salt: salt, hash: hash, iterations: row.int("iterations"))
        }
    }

    /// Creates the account. False when one already exists, so a second setup can never replace it.
    public func create(username: String, password: String) throws -> Bool {
        guard try get() == nil else { return false }
        let salt = PasswordHash.randomSalt()
        let hash = PasswordHash.derive(password: password, salt: salt, iterations: PasswordHash.iterations)
        let changed = try database.execute("INSERT OR IGNORE INTO admin (id, username, salt, hash, iterations) VALUES (1, ?, ?, ?, ?)",
                                           [.text(username), .text(salt.base64EncodedString()), .text(hash.base64EncodedString()), .int(PasswordHash.iterations)])
        return changed == 1
    }
}
