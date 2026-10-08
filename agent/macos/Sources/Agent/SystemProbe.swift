import Darwin
import Foundation
import AgentCore
import MSCore

/// What this Mac is. Measured once at start (the GPU list is slow to read), except the disk, which is asked each time.
struct SystemProbe {
    let specs: MachineSpecs

    private static let bytesPerMb = 1024 * 1024
    private static let bytesPerGb = 1_000_000_000
    private static let profilerPath = "/usr/sbin/system_profiler"

    static func measure() async -> SystemProbe {
        let gpu = (try? await CommandRunner.run(profilerPath, ["SPDisplaysDataType", "-json"], timeout: 20)).map(GpuParser.parse) ?? []
        let info = ProcessInfo.processInfo
        return SystemProbe(specs: MachineSpecs(os: "macos", arch: machine(), cpuCores: info.activeProcessorCount,
                                                ramTotalMb: Int(info.physicalMemory / UInt64(bytesPerMb)), diskTotalGb: diskGb(\.volumeTotalCapacity) ?? 1, gpu: gpu))
    }

    /// Free space the file system reports for the boot volume, in GB, or nil if it cannot be read.
    static func availableDiskGb() -> Int? {
        guard let bytes = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(bytes) / bytesPerGb
    }

    private static func diskGb(_ key: KeyPath<URLResourceValues, Int?>) -> Int? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey]), let bytes = values[keyPath: key] else { return nil }
        return bytes / bytesPerGb
    }

    private static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    }
}
