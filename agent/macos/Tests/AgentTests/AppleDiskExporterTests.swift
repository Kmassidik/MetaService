import XCTest
@testable import Agent

final class AppleDiskExporterTests: XCTestCase {
    func testFailedExportKeepsItsReasonAndLeavesNoPartialBackup() throws {
        let folder = FileManager.default.uniqueTemporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rootfs = folder.appendingPathComponent("rootfs.ext4").path
        let archive = folder.appendingPathComponent("backup.tar").path
        XCTAssertTrue(FileManager.default.createFile(atPath: rootfs, contents: Data("not ext4".utf8)))

        XCTAssertThrowsError(try AppleDiskExporter.export(rootfs: rootfs, archive: archive)) { error in
            XCTAssertTrue(String(describing: error).contains("superblock"), "the useful exporter reason was lost: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive + ".partial"))
    }
}
