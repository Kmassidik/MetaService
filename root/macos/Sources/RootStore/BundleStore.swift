import CryptoKit
import Foundation
import RootCore

public struct BundleRow: Encodable, Equatable {
    public let version: String
    public let platform: String
    public let sha256: String
    public let size: Int
    public let pinned: Bool
}

public struct BundleOverview: Encodable, Equatable {
    public let bundles: [BundleRow]
    public let pinned: String?
    public let previous: String?

    enum CodingKeys: String, CodingKey { case bundles, pinned, previous }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(bundles, forKey: .bundles)
        try box.encode(pinned, forKey: .pinned)
        try box.encode(previous, forKey: .previous)
    }
}

public enum BundleError: Error, Equatable {
    case unknownVersion
    case nothingToRollBackTo
}

/// The bundles the Root can hand out, and which version is pinned. Bundles are files in one folder on the Root machine;
/// nothing can be uploaded over the network.
public struct BundleStore {
    private let database: Database
    public let directory: String
    public static let maxBytes = 64 * 1024 * 1024
    private static let chunk = 1 << 20

    public init(_ database: Database, directory: String) {
        self.database = database
        self.directory = directory
    }

    /// Reads the folder: every well-named file under the size limit becomes (or stays) a row; rows whose file is gone are dropped.
    public func rescan(now: Date) throws {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).filter { BundleFile(fileName: $0) != nil }
        let known = Dictionary(uniqueKeysWithValues: try database.query("SELECT file, size FROM bundles").map { ($0.string("file"), $0.int("size")) })
        for name in names {
            try register(name, known: known, now: now)
        }
        for gone in known.keys where !names.contains(gone) { try database.execute("DELETE FROM bundles WHERE file = ?", [.text(gone)]) }
    }

    private func register(_ name: String, known: [String: Int], now: Date) throws {
        guard let parsed = BundleFile(fileName: name) else { return }
        let path = directory + "/" + name
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard (1...Self.maxBytes).contains(size), (attributes[.type] as? FileAttributeType) == .typeRegular else { return }
        guard known[name] != size, let digest = Self.sha256(path) else { return }
        try database.execute("INSERT OR REPLACE INTO bundles (version, platform, sha256, size, file, added_at) VALUES (?, ?, ?, ?, ?, ?)",
                             [.text(parsed.version), .text(parsed.platform), .text(digest), .int(size), .text(name), .int(Int(now.timeIntervalSince1970))])
    }

    public func overview(now: Date) throws -> BundleOverview {
        try rescan(now: now)
        let pinnedVersion = try pinned()
        let rows = try database.query("SELECT version, platform, sha256, size FROM bundles").map {
            BundleRow(version: $0.string("version"), platform: $0.string("platform"), sha256: $0.string("sha256"), size: $0.int("size"), pinned: $0.string("version") == pinnedVersion)
        }
        let sorted = rows.sorted { BundleFile.isOlder($1.version, than: $0.version) || ($0.version == $1.version && $0.platform < $1.platform) }
        return BundleOverview(bundles: sorted, pinned: pinnedVersion, previous: try previous())
    }

    public func find(version: String, platform: String) throws -> (sha256: String, path: String)? {
        guard let row = try database.query("SELECT sha256, file FROM bundles WHERE version = ? AND platform = ?", [.text(version), .text(platform)]).first else { return nil }
        return (row.string("sha256"), directory + "/" + row.string("file"))
    }

    // MARK: pins

    public func pinned() throws -> String? {
        try database.query("SELECT version FROM bundle_pins ORDER BY id DESC LIMIT 1").first?.string("version")
    }

    /// The version that was pinned before the current one, if it was a different one.
    public func previous() throws -> String? {
        let now = try pinned()
        return try database.query("SELECT version FROM bundle_pins ORDER BY id DESC LIMIT 20").map { $0.string("version") }.first { $0 != now }
    }

    public func pin(version: String, actor: String, now: Date) throws {
        try rescan(now: now)
        guard try database.query("SELECT 1 AS found FROM bundles WHERE version = ?", [.text(version)]).isEmpty == false else { throw BundleError.unknownVersion }
        try database.execute("INSERT INTO bundle_pins (version, pinned_at, actor) VALUES (?, ?, ?)", [.text(version), .int(Int(now.timeIntervalSince1970)), .text(actor)])
    }

    /// Pins the version that came before. The version being left stays on file, so going forward again is one more pin.
    public func rollback(actor: String, now: Date) throws -> String {
        guard let target = try previous() else { throw BundleError.nothingToRollBackTo }
        try pin(version: target, actor: actor, now: now)
        return target
    }

    static func sha256(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try? handle.read(upToCount: chunk), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The access key of each chat, kept encrypted. Target is the machine name, or "machine/workload".
public struct ChatAccessStore {
    private let database: Database

    public init(_ database: Database) { self.database = database }

    public func set(target: String, sealedKey: String, port: Int, now: Date) throws {
        try database.execute("INSERT OR REPLACE INTO chat_access (target, key_sealed, port, updated_at) VALUES (?, ?, ?, ?)",
                             [.text(target), .text(sealedKey), .int(port), .int(Int(now.timeIntervalSince1970))])
    }

    public func get(target: String) throws -> (sealedKey: String, port: Int)? {
        try database.query("SELECT key_sealed, port FROM chat_access WHERE target = ?", [.text(target)]).first.map { ($0.string("key_sealed"), $0.int("port")) }
    }

    /// Every chat key, as (target, sealed key). A few rows at most: one per machine and workload that has the chat.
    public func all() throws -> [(target: String, sealedKey: String)] {
        try database.query("SELECT target, key_sealed FROM chat_access").map { ($0.string("target"), $0.string("key_sealed")) }
    }

    public func remove(target: String) throws {
        try database.execute("DELETE FROM chat_access WHERE target = ? OR target LIKE ? ESCAPE '\\'", [.text(target), .text(target.replacingOccurrences(of: "%", with: "") + "/%")])
    }
}
