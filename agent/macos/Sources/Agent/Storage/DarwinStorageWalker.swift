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
        let reader: UnsafeMutablePointer<DIR>
        let path: String
        let entry, rest: StorageEntry
        let depth: Int

        init(reader: UnsafeMutablePointer<DIR>, path: String, entry: StorageEntry, depth: Int) {
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
        guard let reader = Darwin.opendir(root) else { throw posixFailure("the disk could not be read") }
        let rootEntry = folder(name: rootName, meta: meta)
        var stack = [Open(reader: reader, path: root, entry: rootEntry, depth: 0)]
        var devices = allowedDevices
        devices.insert(Self.device(meta))
        var linked = Set<Link>()
        var entries: UInt64 = 0
        var unreadable: UInt64 = 0

        while let top = stack.last {
            errno = 0
            let found = Darwin.readdir(top.reader)
            guard let found else {
                let readError = errno
                Darwin.closedir(top.reader)
                let done = stack.removeLast().finish()
                if readError != 0 { unreadable += 1 }
                guard let parent = stack.last else { return DarwinStorageWalked(root: done, entries: entries, unreadable: unreadable) }
                parent.attach(done, floor: floor, keepDepth: keepDepth)
                continue
            }
            let name = fileName(found)
            if name == "." || name == ".." { continue }
            entries += 1
            top.entry.noteChild(named: name)
            let path = join(top.path, name)
            var childMeta = Darwin.stat()
            // A file vanishing after its directory was listed needs no error and contributes nothing.
            guard Darwin.lstat(path, &childMeta) == 0 else { counters.addEntry(); continue }
            guard isDirectory(childMeta) else {
                attachFile(top, name: name, meta: childMeta, linked: &linked, floor: floor, keepDepth: keepDepth)
                continue
            }
            let device = Self.device(childMeta)
            if !devices.contains(device) || skip.contains(path) { counters.addEntry(); continue }
            guard let childReader = Darwin.opendir(path) else {
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

    private func attachFile(_ top: Open, name: String, meta: Darwin.stat, linked: inout Set<Link>, floor: UInt64, keepDepth: Int) {
        let link = Link(device: Self.device(meta), inode: UInt64(meta.st_ino))
        let counted = meta.st_nlink <= 1 || linked.insert(link).inserted
        let bytes = counted ? Self.allocated(meta) : 0
        counters.addEntry(bytes: bytes)
        let file = StorageEntry(name: name, type: .file, bytes: bytes, files: 1, modified: Int64(meta.st_mtimespec.tv_sec))
        top.attach(file, floor: floor, keepDepth: keepDepth)
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
