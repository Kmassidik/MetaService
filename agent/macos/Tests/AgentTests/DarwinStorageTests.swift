import Darwin
import XCTest
import AgentCore
@testable import Agent

final class DarwinStorageTests: XCTestCase {
    private var root = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "ms-storage-mac-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        _ = chmod(root + "/locked", 0o700)
        try? FileManager.default.removeItem(atPath: root)
    }

    private func write(_ relative: String, _ size: Int) throws {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
        try Data(repeating: 7, count: size).write(to: URL(fileURLWithPath: path))
    }

    private func taken(_ relative: String = "") throws -> UInt64 {
        var meta = Darwin.stat()
        XCTAssertEqual(Darwin.lstat(root + (relative.isEmpty ? "" : "/" + relative), &meta), 0)
        return UInt64(meta.st_blocks) * 512
    }

    private func walk(floor: UInt64, depth: Int = 24, skip: Set<String> = []) throws -> DarwinStorageWalked {
        try DarwinStorageWalker(root: root, allowedDevices: [], skip: skip, counters: StorageCounters()).walk(floor: floor, keepDepth: depth)
    }

    private func child(_ parent: StorageEntry, _ name: String) throws -> StorageEntry {
        try XCTUnwrap(parent.children.first { $0.name == name })
    }

    private func map(_ marker: UInt64) -> StorageMap {
        let disk = StorageDisk(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        let node = StorageNode(parent: -1, name: "/", type: .dir, bytes: marker, files: 0, items: 0, kind: .other, reclaim: nil, modified: nil)
        return StorageMap(root: "/", finishedAt: "2026-10-26T00:00:00Z", seconds: 0.1, entries: 1, unreadable: 0, disk: disk, nodes: [node])
    }

    func testStorageCacheRoundTripUsesPrivatePermissions() throws {
        let path = root + "/storage.json"
        let cache = DarwinStorageCache(path: path)
        let expected = map(42)

        try cache.save(expected)

        XCTAssertEqual(cache.load(), expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(mode & 0o777, 0o600)
    }

    func testMissingAndCorruptStorageCacheAreRejected() throws {
        let path = root + "/storage.json"
        let cache = DarwinStorageCache(path: path)
        XCTAssertNil(cache.load())

        try Data("not a storage map".utf8).write(to: URL(fileURLWithPath: path))

        XCTAssertNil(cache.load())
    }

    func testStorageCacheOlderThanADayIsIgnored() throws {
        let path = root + "/storage.json"
        let cache = DarwinStorageCache(path: path)
        try cache.save(map(42))
        let old = Date.distantPast
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)

        XCTAssertNil(cache.load())
    }

    func testAllocatedSizesAndSmallEntriesJoinRest() throws {
        try write("big.bin", 600_000)
        try write("notes/note.md", 100)
        let walked = try walk(floor: 100_000)
        let big = try child(walked.root, "big.bin")
        let rest = try XCTUnwrap(walked.root.children.first { $0.type == .rest })
        XCTAssertEqual(big.bytes, try taken("big.bin"))
        XCTAssertEqual(rest.files, 1)
        XCTAssertEqual(rest.items, 1)
        XCTAssertEqual(walked.root.files, 2)
        XCTAssertEqual(walked.unreadable, 0)
        XCTAssertEqual(walked.root.bytes, try taken() + walked.root.children.reduce(UInt64(0)) { $0 + $1.bytes })
    }

    func testHardLinkedFileIsChargedOnce() throws {
        try write("a/data.bin", 500_000)
        try FileManager.default.createDirectory(atPath: root + "/b", withIntermediateDirectories: true)
        try FileManager.default.linkItem(atPath: root + "/a/data.bin", toPath: root + "/b/data.bin")
        let tree = try walk(floor: 0).root
        let a = try child(tree, "a")
        let b = try child(tree, "b")
        let chargedA = a.bytes - (try taken("a"))
        let chargedB = b.bytes - (try taken("b"))
        XCTAssertEqual(chargedA + chargedB, try taken("a/data.bin"))
    }

    func testKeepDepthFoldsEverythingBelowIt() throws {
        try write("one/two/three/big.bin", 300_000)
        let tree = try walk(floor: 1, depth: 1).root
        let one = try child(tree, "one")
        XCTAssertEqual(one.children.count, 1)
        XCTAssertEqual(one.children[0].type, .rest)
        XCTAssertEqual(tree.files, 1)
    }

    func testSkippedMountAndDirectDataMountAreNotWalkedTwice() throws {
        try write("Users/big.bin", 300_000)
        try write("System/Volumes/Data/Users/big.bin", 300_000)
        try write("mnt/other/big.bin", 300_000)
        let skip: Set<String> = [root + "/System/Volumes/Data", root + "/mnt/other"]
        let tree = try walk(floor: 1, skip: skip).root
        XCTAssertEqual(tree.files, 1)
        XCTAssertNotNil(try? child(tree, "Users"))
        XCTAssertNil(tree.children.first { $0.name == "mnt" }?.children.first { $0.name == "other" })
    }

    func testUnreadableFolderIsReportedAndItsOwnAllocationRetained() throws {
        try XCTSkipIf(geteuid() == 0, "root can open mode-000 folders")
        try write("locked/big.bin", 300_000)
        _ = chmod(root + "/locked", 0)
        let walked = try walk(floor: 0)
        XCTAssertEqual(walked.unreadable, 1)
        XCTAssertEqual(walked.root.files, 0)
        XCTAssertEqual(try child(walked.root, "locked").bytes, try taken("locked"))
    }

    func testMountedVolumesIdentifyRootAndDiskTotalsAreExact() throws {
        let volumes = try DarwinStorageVolumes.mounted()
        let rootVolume = try XCTUnwrap(volumes.first { $0.mount == "/" })
        var meta = Darwin.stat()
        XCTAssertEqual(Darwin.lstat("/", &meta), 0)
        XCTAssertEqual(rootVolume.device, DarwinStorageWalker.device(meta))
        let disk = try DarwinStorageVolumes.disk(at: "/")
        XCTAssertGreaterThan(disk.totalBytes, 0)
        XCTAssertLessThanOrEqual(disk.usedBytes + disk.freeBytes, disk.totalBytes)
    }

    func testNegativeDarwinMetadataCannotCrashAScan() {
        var meta = Darwin.stat()
        meta.st_dev = -1
        meta.st_blocks = -8
        XCTAssertEqual(DarwinStorageWalker.device(meta), UInt64(bitPattern: Int64(-1)))
        XCTAssertEqual(DarwinStorageWalker.allocated(meta), 0)
    }

    func testAPFSPlanIncludesOnlyDataTwinAndSkipsRealMounts() {
        let rootVolume = DarwinStorageVolume(mount: "/", source: "/dev/disk3s1s1", fs: "apfs", device: 1)
        let data = DarwinStorageVolume(mount: "/System/Volumes/Data", source: "/dev/disk3s5", fs: "apfs", device: 2)
        let preboot = DarwinStorageVolume(mount: "/System/Volumes/Preboot", source: "/dev/disk3s2", fs: "apfs", device: 3)
        let external = DarwinStorageVolume(mount: "/Volumes/External", source: "/dev/disk4s1", fs: "apfs", device: 4)
        let plan = DarwinStorageMountPlan(root: "/", volumes: [rootVolume, data, preboot, external])
        XCTAssertEqual(plan.allowedDevices, [1, 2])
        XCTAssertTrue(plan.skip.contains("/System/Volumes/Data"))
        XCTAssertTrue(plan.skip.contains("/System/Volumes/Preboot"))
        XCTAssertTrue(plan.skip.contains("/Volumes/External"))
        XCTAssertFalse(plan.skip.contains("/Users"), "firmlink targets are traversed once, not skipped as mounts")
    }
}
