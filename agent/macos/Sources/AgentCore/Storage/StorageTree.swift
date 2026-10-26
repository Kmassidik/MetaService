import Foundation

struct StorageMarks: OptionSet {
    let rawValue: UInt8
    static let cargo = StorageMarks(rawValue: 1)
    static let package = StorageMarks(rawValue: 1 << 1)
    static let applicationSupport = StorageMarks(rawValue: 1 << 2)
    static let gitStore = StorageMarks(rawValue: 0b111 << 3)

    static func named(_ name: String) -> StorageMarks {
        switch name {
        case "Cargo.toml": return .cargo
        case "package.json": return .package
        case "Application Support": return .applicationSupport
        case "objects": return StorageMarks(rawValue: 1 << 3)
        case "refs": return StorageMarks(rawValue: 1 << 4)
        case "HEAD": return StorageMarks(rawValue: 1 << 5)
        default: return []
        }
    }
}

/// A mutable scan tree. Kept entries own their smaller descendants only until those are folded into a rest.
public final class StorageEntry {
    public let name: String
    public let type: StorageEntryType
    public private(set) var bytes, files, items: UInt64
    public private(set) var modified: Int64?
    public internal(set) var children: [StorageEntry] = []
    var marks: StorageMarks = []
    var kind: StorageKind = .other
    var reclaim: StorageReclaim?

    public init(name: String, type: StorageEntryType, bytes: UInt64, files: UInt64 = 0, modified: Int64? = nil) {
        self.name = name
        self.type = type
        self.bytes = bytes
        self.files = files
        self.items = 0
        self.modified = modified
    }

    public static func rest() -> StorageEntry { StorageEntry(name: "", type: .rest, bytes: 0) }

    public func noteChild(named name: String) {
        items += 1
        marks.insert(.named(name))
    }

    public func attach(_ child: StorageEntry, floor: UInt64, rest: StorageEntry) {
        bytes += child.bytes
        files += child.files
        modified = newest(modified, child.modified)
        if child.bytes >= floor {
            children.append(child)
        } else {
            rest.absorb(child)
        }
    }

    public func finish(rest: StorageEntry) {
        if rest.items > 0 { children.append(rest) }
        children.sort { $0.bytes > $1.bytes }
    }

    public func absorb(_ other: StorageEntry) {
        bytes += other.bytes
        files += other.files
        items += other.type == .rest ? other.items : 1
        modified = newest(modified, other.modified)
    }

    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }
}

func newest(_ left: Int64?, _ right: Int64?) -> Int64? {
    guard let left else { return right }
    guard let right else { return left }
    return max(left, right)
}

public enum StorageTree {
    public static let maxNodes = 12_000
    private static let maxNameCharacters = 255
    private static let maxFoldRounds = 16

    /// Folds the smallest subtrees into their parent's rest without losing any byte or file totals.
    public static func fit(_ root: StorageEntry, max: Int = maxNodes) {
        var floor: UInt64 = 0
        for _ in 0..<maxFoldRounds {
            let count = root.count
            guard count > max else { return }
            var sizes: [UInt64] = []
            sizes.reserveCapacity(count)
            for child in root.children { collectSizes(child, into: &sizes) }
            sizes.sort(by: >)
            let keep = Swift.max(Swift.min(Swift.max(max - 1, 1), sizes.count), 1)
            floor = Swift.max(sizes[keep - 1], floor + 1)
            fold(root, floor: floor)
        }
        guard root.count > max else { return }
        fold(root, floor: .max)
    }

    /// Depth-first, parents before children, largest sibling first; every parent points to an earlier directory.
    public static func flatten(_ root: StorageEntry) -> [StorageNode] {
        var nodes: [StorageNode] = []
        nodes.reserveCapacity(root.count)
        var stack: [(StorageEntry, Int)] = [(root, -1)]
        while let (entry, parent) = stack.popLast() {
            let place = nodes.count
            nodes.append(StorageNode(parent: parent, name: String(entry.name.prefix(maxNameCharacters)), type: entry.type,
                                     bytes: entry.bytes, files: entry.files, items: entry.items, kind: entry.kind,
                                     reclaim: entry.reclaim, modified: entry.modified))
            for child in entry.children.reversed() { stack.append((child, place)) }
        }
        return nodes
    }

    private static func collectSizes(_ entry: StorageEntry, into sizes: inout [UInt64]) {
        sizes.append(entry.bytes)
        for child in entry.children { collectSizes(child, into: &sizes) }
    }

    private static func fold(_ entry: StorageEntry, floor: UInt64) {
        let old = entry.children
        entry.children.removeAll(keepingCapacity: true)
        let rest = StorageEntry.rest()
        rest.kind = entry.kind
        rest.reclaim = entry.reclaim
        for child in old {
            if child.bytes >= floor, child.type != .rest {
                fold(child, floor: floor)
                entry.children.append(child)
            } else {
                rest.absorb(child)
            }
        }
        if rest.items > 0 { entry.children.append(rest) }
        entry.children.sort { $0.bytes > $1.bytes }
    }
}
