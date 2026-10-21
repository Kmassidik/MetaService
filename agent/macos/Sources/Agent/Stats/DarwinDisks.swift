import Darwin
import Foundation
import AgentCore

/// Mounted real volumes. The system's own helper volumes under /System/Volumes and the virtual-memory volume are not listed.
enum DarwinDisks {
    private static let realFileSystems: Set<String> = ["apfs", "hfs", "exfat", "msdos", "ntfs", "ufs"]
    private static let hiddenMountPrefixes = ["/System/Volumes/", "/private/var/vm", "/Library/Developer/CoreSimulator"]

    static func read() -> [DiskReading] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }
        var buffer = Array(repeating: Darwin.statfs(), count: Int(count))
        let filled = getfsstat(&buffer, Int32(MemoryLayout<statfs>.stride) * count, MNT_NOWAIT)
        guard filled > 0 else { return [] }
        return buffer.prefix(Int(filled)).compactMap(reading)
    }

    private static func reading(_ entry: statfs) -> DiskReading? {
        let fs = text(entry.f_fstypename), mount = text(entry.f_mntonname)
        guard realFileSystems.contains(fs), !hiddenMountPrefixes.contains(where: { mount.hasPrefix($0) }) else { return nil }
        let block = UInt64(entry.f_bsize)
        return DiskReading(mount: mount, name: volumeName(mount), fs: fs, totalBytes: UInt64(entry.f_blocks) * block, freeBytes: UInt64(entry.f_bavail) * block)
    }

    private static func volumeName(_ mount: String) -> String {
        let named = try? URL(fileURLWithPath: mount).resourceValues(forKeys: [.volumeNameKey]).volumeName
        return named ?? (mount as NSString).lastPathComponent
    }

    private static func text<T>(_ field: T) -> String {
        withUnsafeBytes(of: field) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}
