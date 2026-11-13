import Darwin
import Foundation
import AgentCore

struct DarwinStorageWalked {
    let root: StorageEntry
    let entries, unreadable: UInt64
}

/// A streaming, iterative lstat/readdir walk: no symlinks, mount crossings, writes, or recursion through deep trees.
struct DarwinStorageWalker {
    let root: String
    let allowedDevices: Set<UInt64>
    let skip: Set<String>
    let counters: StorageCounters

    private struct Link: Hashable { let device, inode: UInt64 }

    private final class Open {
        let reader: Int32
        let path: String
        let entry, rest: StorageEntry
        let depth: Int
        var batch: [DarwinBulkItem] = []
        var next = 0
        var drained = false

        init(reader: Int32, path: String, entry: StorageEntry, depth: Int) {
            self.reader = reader
            self.path = path
            self.entry = entry
            self.rest = StorageEntry.rest()
            self.depth = depth
        }

        func attach(_ child: StorageEntry, floor: UInt64, keepDepth: Int) {
            entry.attach(child, floor: depth >= keepDepth ? .max : floor, rest: rest)
        }

        func finish() -> StorageEntry {
            entry.finish(rest: rest)
            return entry
        }
    }

    func walk(floor: UInt64, keepDepth: Int = 24) throws -> DarwinStorageWalked {
        var meta = Darwin.stat()
        guard Darwin.lstat(root, &meta) == 0 else { throw posixFailure("the disk could not be read") }
        let reader = Darwin.open(root, O_RDONLY | O_DIRECTORY)
        guard reader >= 0 else { throw posixFailure("the disk could not be read") }
        let rootEntry = folder(name: rootName, meta: meta)
        var stack = [Open(reader: reader, path: root, entry: rootEntry, depth: 0)]
        var devices = allowedDevices
        devices.insert(Self.device(meta))
        var linked = Set<Link>()
        var entries: UInt64 = 0
        var unreadable: UInt64 = 0

        let buffer = DarwinBulkBuffer()
        while let top = stack.last {
            guard let item = try nextItem(of: top, buffer: buffer, unreadable: &unreadable) else {
                Darwin.close(top.reader)
                let done = stack.removeLast().finish()
                guard let parent = stack.last else { return DarwinStorageWalked(root: done, entries: entries, unreadable: unreadable) }
                parent.attach(done, floor: floor, keepDepth: keepDepth)
                continue
            }
            let name = item.name
            entries += 1
            top.entry.noteChild(named: name)
            guard item.isDirectory else {
                attachFile(top, item: item, linked: &linked, floor: floor, keepDepth: keepDepth)
                continue
            }
            let path = join(top.path, name)
            var childMeta = Darwin.stat()
            guard Darwin.lstat(path, &childMeta) == 0 else { counters.addEntry(); continue }
            if !devices.contains(Self.device(childMeta)) || skip.contains(path) { counters.addEntry(); continue }
            let childReader = Darwin.open(path, O_RDONLY | O_DIRECTORY)
            guard childReader >= 0 else {
                unreadable += 1
                counters.addEntry()
                top.attach(folder(name: name, meta: childMeta), floor: floor, keepDepth: keepDepth)
                continue
            }
            counters.addEntry()
            stack.append(Open(reader: childReader, path: path, entry: folder(name: name, meta: childMeta), depth: top.depth + 1))
        }
        throw StorageScanFailure("the disk walk ended unexpectedly")
    }

    private func attachFile(_ top: Open, item: DarwinBulkItem, linked: inout Set<Link>, floor: UInt64, keepDepth: Int) {
        let link = Link(device: item.device, inode: item.inode)
        let counted = item.links <= 1 || linked.insert(link).inserted
        let bytes = counted ? item.allocated : 0
        counters.addEntry(bytes: bytes)
        let file = StorageEntry(name: item.name, type: .file, bytes: bytes, files: 1, modified: item.modified)
        top.attach(file, floor: floor, keepDepth: keepDepth)
    }

    /// One bulk read returns many names with their sizes, so a file needs no lstat of its own.
    private func nextItem(of top: Open, buffer: DarwinBulkBuffer, unreadable: inout UInt64) throws -> DarwinBulkItem? {
        while top.next >= top.batch.count {
            if top.drained { return nil }
            let read = buffer.read(from: top.reader)
            guard read.failed == false else { unreadable += 1; top.drained = true; return nil }
            top.batch = read.items
            top.next = 0
            if read.items.isEmpty { top.drained = true }
        }
        defer { top.next += 1 }
        return top.batch[top.next]
    }

    private var rootName: String { root == "/" ? "/" : URL(fileURLWithPath: root).lastPathComponent }

    private func folder(name: String, meta: Darwin.stat) -> StorageEntry {
        StorageEntry(name: name, type: .dir, bytes: Self.allocated(meta), modified: Int64(meta.st_mtimespec.tv_sec))
    }

    static func device(_ meta: Darwin.stat) -> UInt64 { UInt64(bitPattern: Int64(meta.st_dev)) }

    static func allocated(_ meta: Darwin.stat) -> UInt64 { UInt64(Swift.max(0, meta.st_blocks)) * 512 }

    private func isDirectory(_ meta: Darwin.stat) -> Bool { meta.st_mode & S_IFMT == S_IFDIR }

    private func join(_ parent: String, _ name: String) -> String { parent == "/" ? "/\(name)" : "\(parent)/\(name)" }

    private func fileName(_ entry: UnsafeMutablePointer<dirent>) -> String {
        withUnsafeBytes(of: entry.pointee.d_name) { bytes in
            String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
        }
    }
}
