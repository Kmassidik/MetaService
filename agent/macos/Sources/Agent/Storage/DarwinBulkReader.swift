import Darwin
import Foundation

/// One directory entry as read by getattrlistbulk: everything the walker needs for a file without a separate lstat.
struct DarwinBulkItem {
    let name: String
    let isDirectory: Bool
    let device, inode: UInt64
    let links: UInt32
    let allocated: UInt64
    let modified: Int64
}

struct DarwinBulkRead {
    let items: [DarwinBulkItem]
    let failed: Bool
}

/// Reads directories with getattrlistbulk (hundreds of entries per system call). The buffer is reused for every directory.
final class DarwinBulkBuffer {
    private static let size = 256 * 1024
    private static let wanted: UInt32 = UInt32(ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE | ATTR_CMN_MODTIME | ATTR_CMN_FILEID)
    private static let wantedFile: UInt32 = UInt32(ATTR_FILE_LINKCOUNT | ATTR_FILE_ALLOCSIZE)
    private let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)

    deinit { memory.deallocate() }

    func read(from descriptor: Int32) -> DarwinBulkRead {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(UInt32(ATTR_CMN_RETURNED_ATTRS) | Self.wanted)
        list.fileattr = attrgroup_t(Self.wantedFile)
        let count = getattrlistbulk(descriptor, &list, memory, Self.size, 0)
        guard count >= 0 else { return DarwinBulkRead(items: [], failed: true) }
        var items: [DarwinBulkItem] = []
        items.reserveCapacity(Int(count))
        var cursor = memory
        for _ in 0..<count {
            let length = Int(cursor.loadUnaligned(as: UInt32.self))
            if let item = Self.parse(cursor) { items.append(item) }
            cursor += length
        }
        return DarwinBulkRead(items: items, failed: false)
    }

    /// Fields come packed in attribute-bit order, only the ones the kernel says it returned.
    private static func parse(_ entry: UnsafeMutableRawPointer) -> DarwinBulkItem? {
        var at = 4
        func take<T>(_ type: T.Type) -> T { defer { at += MemoryLayout<T>.size }; return entry.loadUnaligned(fromByteOffset: at, as: T.self) }
        let common = entry.loadUnaligned(fromByteOffset: at, as: UInt32.self)
        let file = entry.loadUnaligned(fromByteOffset: at + 12, as: UInt32.self)
        at += 20
        let needed = wanted
        guard common & needed == needed else { return nil }
        let nameAt = at
        let reference = take(attrreference_t.self)
        let device = UInt64(bitPattern: Int64(take(Int32.self)))
        let kind = take(UInt32.self)
        let time = take(timespec.self)
        let inode = take(UInt64.self)
        let isDirectory = kind == UInt32(VDIR.rawValue)
        var links: UInt32 = 1
        var allocated: UInt64 = 0
        if !isDirectory, file & wantedFile == wantedFile {
            links = take(UInt32.self)
            allocated = UInt64(Swift.max(0, take(Int64.self)))
        }
        let namePointer = (entry + nameAt + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
        return DarwinBulkItem(name: String(cString: namePointer), isDirectory: isDirectory, device: device, inode: inode,
                              links: links, allocated: allocated, modified: Int64(time.tv_sec))
    }
}
