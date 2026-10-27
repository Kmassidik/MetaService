import AgentCore
import ContainerizationEXT4
import Foundation
import SystemPackage

/// Exports an Apple Container rootfs with the preallocated-extent fix. Apple's CLI 1.1.0 attempts a zero-byte read and mistakes it for a bad block.
enum AppleDiskExporter {
    static func rootfsPath(id: String, home: String = NSHomeDirectory()) -> String {
        home + "/Library/Application Support/com.apple.container/containers/" + AppleContainer.name(for: id) + "/rootfs.ext4"
    }

    /// Runs in the child process so export I/O and memory cannot block or kill the helper.
    static func export(id: String, to archive: String, timeout: TimeInterval) async throws {
        _ = try await ProcessContainerCLI(path: CommandLine.arguments[0]).run(["--export-rootfs", rootfsPath(id: id), archive], timeout: timeout)
    }

    /// Writes only a complete archive. A failure removes the partial file and preserves any previous backup.
    static func export(rootfs: String, archive: String) throws {
        let partial = archive + ".partial"
        defer { try? FileManager.default.removeItem(atPath: partial) }
        let reader = try EXT4.EXT4Reader(blockDevice: FilePath(rootfs))
        try reader.export(archive: FilePath(partial))
        try FileManager.default.moveItem(atPath: partial, toPath: archive)
    }
}
