import Darwin
import Foundation
import AgentCore

struct DarwinStorageVolume {
    let mount, source, fs: String
    let device: UInt64?
}

struct DarwinStorageMountPlan {
    let allowedDevices: Set<UInt64>
    let skip: Set<String>

    /// Include the root and its APFS Data twin, but enter Data only through firmlinks such as /Users.
    /// Every real mount point is skipped, which prevents a second walk through /System/Volumes/Data.
    init(root: String, volumes: [DarwinStorageVolume]) {
        let rootVolume = volumes.first { $0.mount == root }
        var devices = Set<UInt64>()
        if let device = rootVolume?.device { devices.insert(device) }
        if let device = Self.dataTwin(root: rootVolume, volumes: volumes)?.device { devices.insert(device) }
        allowedDevices = devices
        skip = Set(volumes.map(\.mount).filter { $0 != root })
    }

    private static func dataTwin(root: DarwinStorageVolume?, volumes: [DarwinStorageVolume]) -> DarwinStorageVolume? {
        guard let root, root.fs == "apfs" else { return nil }
        return volumes.first { volume in
            volume.fs == "apfs" && volume.mount == "/System/Volumes/Data" && container(volume.source) == container(root.source)
        }
    }

    /// APFS sources look like disk3s1s1 (a snapshot) and disk3s5 (Data); disk3 names their shared container.
    private static func container(_ source: String) -> String {
        let name = URL(fileURLWithPath: source).lastPathComponent
        guard name.hasPrefix("disk"), let split = name.dropFirst(4).firstIndex(of: "s") else { return name }
        return String(name[..<split])
    }
}

enum DarwinStorageVolumes {
    static func disk(at path: String) throws -> StorageDisk {
        var value = Darwin.statfs()
        guard statfs(path, &value) == 0 else { throw posixFailure("the size of the disk could not be read") }
        let block = UInt64(value.f_bsize)
        let total = UInt64(value.f_blocks) * block
        let free = Swift.min(UInt64(value.f_bavail) * block, total)
        return StorageDisk(totalBytes: total, usedBytes: total - free, freeBytes: free)
    }

    static func mounted() throws -> [DarwinStorageVolume] {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { throw posixFailure("mounted volumes could not be read") }
        var buffer = Array(repeating: Darwin.statfs(), count: Int(count))
        let filled = getfsstat(&buffer, Int32(MemoryLayout<Darwin.statfs>.stride) * count, MNT_NOWAIT)
        guard filled > 0 else { throw posixFailure("mounted volumes could not be read") }
        return buffer.prefix(Int(filled)).map(volume)
    }

    private static func volume(_ value: Darwin.statfs) -> DarwinStorageVolume {
        let mount = text(value.f_mntonname)
        let device = needsDevice(mount) ? device(at: mount) : nil
        return DarwinStorageVolume(mount: mount, source: text(value.f_mntfromname), fs: text(value.f_fstypename), device: device)
    }

    private static func needsDevice(_ mount: String) -> Bool {
        mount == "/" || mount == "/System/Volumes/Data"
    }

    private static func device(at path: String) -> UInt64? {
        var meta = Darwin.stat()
        guard stat(path, &meta) == 0 else { return nil }
        return DarwinStorageWalker.device(meta)
    }

    private static func text<T>(_ field: T) -> String {
        withUnsafeBytes(of: field) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

func posixFailure(_ message: String, code: Int32 = errno) -> StorageScanFailure {
    StorageScanFailure("\(message): \(String(cString: strerror(code)))")
}
