import Foundation

/// What a helper says fills its machine's root file system (contract `Storage`, GET /v1/storage): the last finished scan, and whether one runs now.
/// The parent decodes the helper's answer into this and applies the contract's limits again, so a helper that lies or is attacked cannot make the panel draw more than the contract allows.
public struct Storage: Codable, Equatable, Sendable {
    /// 12000 entries with long names fit well inside this.
    public static let maxAnswerBytes = 8 * 1024 * 1024
    public static let maxNodes = 12_000
    public static let maxNameCharacters = 255
    public static let maxErrorCharacters = 300
    public static let maxRootCharacters = 4096
    public static let maxTimeCharacters = 32
    public static let types: Set<String> = ["dir", "file", "rest"]
    /// disktree's kinds of data, plus vms. A kind this parent does not know yet is shown as other.
    public static let kinds: Set<String> = ["code", "agent", "toolchain", "synced", "git", "media", "documents", "cache", "vms", "other"]
    /// disktree's reasons why space could be had back. A reason this parent does not know yet is dropped (null), never guessed.
    public static let reclaims: Set<String> = ["regenerable", "sync_history", "package_store", "build_output", "reinstallable", "sandbox_layers", "snapshots", "trash", "temporary"]

    /// How far the running scan is.
    public struct Progress: Codable, Equatable, Sendable {
        public var entries: Int
        public var bytes: Int
    }

    public var scanning: Bool
    /// Nil when no scan runs.
    public var progress: Progress?
    /// Why the last scan failed, in plain words; nil after a good one.
    public var error: String?
    /// The last finished scan (kept while a new one runs); nil before the first one ends.
    public var map: StorageMap?

    private enum CodingKeys: String, CodingKey { case scanning, progress, error, map }

    /// Written like the contract: every key is always there, a missing value is null.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(scanning, forKey: .scanning)
        try box.encode(progress, forKey: .progress)
        try box.encode(error, forKey: .error)
        try box.encode(map, forKey: .map)
    }
}

/// One finished scan: the folder scanned, how it went, the disk's totals, and the kept entries, a folder before what it holds.
public struct StorageMap: Codable, Equatable, Sendable {
    public struct Disk: Codable, Equatable, Sendable {
        public var totalBytes: Int
        public var usedBytes: Int
        public var freeBytes: Int
    }

    public var root: String
    public var finishedAt: String
    public var seconds: Double
    public var entries: Int
    /// Folders the helper could not open.
    public var unreadable: Int
    public var disk: Disk
    /// The first is the scanned folder itself; siblings come largest first.
    public var nodes: [StorageNode]
}

/// One kept entry of a scan. `parent` is the place in `nodes` of the folder holding it (-1 only for the first). A `rest` stands for the smaller entries of its folder, added together.
public struct StorageNode: Codable, Equatable, Sendable {
    public var parent: Int
    public var name: String
    /// dir, file or rest.
    public var type: String
    public var bytes: Int
    public var files: Int
    public var items: Int
    public var kind: String
    /// Nil when nothing says its space could be had back. The panel only shows it, it never deletes.
    public var reclaim: String?
    /// Unix seconds of the newest change below it; nil when the helper could not say.
    public var modified: Int?

    private enum CodingKeys: String, CodingKey { case parent, name, type, bytes, files, items, kind, reclaim, modified }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(parent, forKey: .parent)
        try box.encode(name, forKey: .name)
        try box.encode(type, forKey: .type)
        try box.encode(bytes, forKey: .bytes)
        try box.encode(files, forKey: .files)
        try box.encode(items, forKey: .items)
        try box.encode(kind, forKey: .kind)
        try box.encode(reclaim, forKey: .reclaim)
        try box.encode(modified, forKey: .modified)
    }
}
