import Foundation

public struct StorageDisk: Codable, Equatable, Sendable {
    public let totalBytes, usedBytes, freeBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }
}

public struct StorageProgress: Codable, Equatable, Sendable {
    public let entries, bytes: UInt64
    public init(entries: UInt64, bytes: UInt64) { self.entries = entries; self.bytes = bytes }
}

public enum StorageEntryType: String, Codable, Sendable {
    case dir, file, rest
}

public enum StorageKind: String, Codable, Sendable {
    case code, agent, toolchain, synced, git, media, documents, cache, vms, other
}

public enum StorageReclaim: String, Codable, Sendable {
    case regenerable, syncHistory = "sync_history"
    case packageStore = "package_store"
    case buildOutput = "build_output"
    case reinstallable, sandboxLayers = "sandbox_layers"
    case snapshots, trash, temporary
}

public struct StorageNode: Codable, Equatable, Sendable {
    public let parent: Int
    public let name: String
    public let type: StorageEntryType
    public let bytes, files, items: UInt64
    public let kind: StorageKind
    public let reclaim: StorageReclaim?
    public let modified: Int64?

    public init(parent: Int, name: String, type: StorageEntryType, bytes: UInt64, files: UInt64, items: UInt64,
                kind: StorageKind, reclaim: StorageReclaim?, modified: Int64?) {
        self.parent = parent
        self.name = name
        self.type = type
        self.bytes = bytes
        self.files = files
        self.items = items
        self.kind = kind
        self.reclaim = reclaim
        self.modified = modified
    }

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

public struct StorageMap: Codable, Equatable, Sendable {
    public let root, finishedAt: String
    public let seconds: Double
    public let entries, unreadable: UInt64
    public let disk: StorageDisk
    public let nodes: [StorageNode]

    public init(root: String, finishedAt: String, seconds: Double, entries: UInt64, unreadable: UInt64,
                disk: StorageDisk, nodes: [StorageNode]) {
        self.root = root
        self.finishedAt = finishedAt
        self.seconds = seconds
        self.entries = entries
        self.unreadable = unreadable
        self.disk = disk
        self.nodes = nodes
    }
}

public struct StorageAnswer: Codable, Equatable, Sendable {
    public let scanning: Bool
    public let progress: StorageProgress?
    public let error: String?
    public let map: StorageMap?

    public init(scanning: Bool, progress: StorageProgress?, error: String?, map: StorageMap?) {
        self.scanning = scanning
        self.progress = progress
        self.error = error
        self.map = map
    }

    private enum CodingKeys: String, CodingKey { case scanning, progress, error, map }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(scanning, forKey: .scanning)
        try box.encode(progress, forKey: .progress)
        try box.encode(error, forKey: .error)
        try box.encode(map, forKey: .map)
    }
}

public struct StorageScanFailure: Error, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
