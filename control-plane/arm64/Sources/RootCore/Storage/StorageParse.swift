import Foundation

public enum StorageError: Error, Equatable {
    case tooBig
    case notAnAnswer
    /// The entries do not make a tree the contract allows: none or too many, a parent that is not an earlier folder, or an unknown type.
    case brokenMap
}

extension Storage {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Reads a helper's answer and holds it to the contract's limits. An answer that is too big, does not have the right shape, or whose entries do not make a tree is refused whole.
    public static func parse(_ data: Data) throws -> Storage {
        guard data.count <= maxAnswerBytes else { throw StorageError.tooBig }
        guard let raw = try? decoder.decode(Storage.self, from: data) else { throw StorageError.notAnAnswer }
        return try raw.limited()
    }

    func limited() throws -> Storage {
        var kept = self
        kept.progress = progress.map { Progress(entries: max($0.entries, 0), bytes: max($0.bytes, 0)) }
        kept.error = error.map { String($0.prefix(Self.maxErrorCharacters)) }
        kept.map = try map?.limited()
        return kept
    }
}

extension StorageMap {
    fileprivate func limited() throws -> StorageMap {
        guard (1...Storage.maxNodes).contains(nodes.count), Self.isTree(nodes) else { throw StorageError.brokenMap }
        return StorageMap(root: String(root.prefix(Storage.maxRootCharacters)), finishedAt: String(finishedAt.prefix(Storage.maxTimeCharacters)),
                          seconds: seconds.isFinite ? max(seconds, 0) : 0, entries: max(entries, 0), unreadable: max(unreadable, 0),
                          disk: Disk(totalBytes: max(disk.totalBytes, 0), usedBytes: max(disk.usedBytes, 0), freeBytes: max(disk.freeBytes, 0)),
                          nodes: nodes.map { $0.limited() })
    }

    /// The first entry has no parent (-1); every other one points at an earlier entry that is a folder. Every type is one the contract names.
    static func isTree(_ nodes: [StorageNode]) -> Bool {
        for (place, node) in nodes.enumerated() {
            guard Storage.types.contains(node.type) else { return false }
            if place == 0 {
                guard node.parent == -1 else { return false }
            } else {
                guard (0..<place).contains(node.parent), nodes[node.parent].type == "dir" else { return false }
            }
        }
        return true
    }
}

extension StorageNode {
    /// A kind or reason this parent does not know yet (a newer helper) is read as other, or as no reason, so the answer is still shown.
    fileprivate func limited() -> StorageNode {
        StorageNode(parent: parent, name: String(name.prefix(Storage.maxNameCharacters)), type: type, bytes: max(bytes, 0), files: max(files, 0), items: max(items, 0),
                    kind: Storage.kinds.contains(kind) ? kind : "other", reclaim: reclaim.flatMap { Storage.reclaims.contains($0) ? $0 : nil }, modified: modified)
    }
}
