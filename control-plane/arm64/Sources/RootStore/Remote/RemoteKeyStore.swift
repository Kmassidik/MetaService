import Foundation

/// The SSH keys the parent logs in with. The private half is stored sealed (encrypted with the Root key, like the Agents' tokens), never in clear.
public struct RemoteKey: Equatable {
    public let name: String
    public let publicKey: String
    public let privateSealed: String

    public init(name: String, publicKey: String, privateSealed: String) {
        self.name = name
        self.publicKey = publicKey
        self.privateSealed = privateSealed
    }
}

public struct RemoteKeyStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func get(_ name: String) throws -> RemoteKey? {
        try database.query("SELECT name, public_key, private_sealed FROM remote_keys WHERE name = ?", [.text(name)]).first.map {
            RemoteKey(name: $0.string("name"), publicKey: $0.string("public_key"), privateSealed: $0.string("private_sealed"))
        }
    }

    /// Keeps a key. A name that already has one is left as it is, so two requests at once cannot replace a key that a machine already trusts.
    public func addIfMissing(_ key: RemoteKey, now: Date) throws {
        try database.execute("INSERT OR IGNORE INTO remote_keys (name, public_key, private_sealed, created_at) VALUES (?, ?, ?, ?)",
                             [.text(key.name), .text(key.publicKey), .text(key.privateSealed), .int(Int(now.timeIntervalSince1970))])
    }

    public func remove(_ name: String) throws {
        try database.execute("DELETE FROM remote_keys WHERE name = ?", [.text(name)])
    }
}
