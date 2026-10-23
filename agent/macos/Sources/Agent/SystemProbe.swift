import Darwin
import Foundation
import AgentCore
import MSCore

/// What this Mac is. Measured once at start (the GPU list is slow to read), except RAM and disk, which `readMachine` asks again each time.
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

    /// A fresh reading of RAM and the boot volume: one physical-memory read and one volume query, no external program. Nil when the volume cannot be read.
    static func readMachine() -> MachineReading? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return MachineReading(ramTotalMb: Int(ProcessInfo.processInfo.physicalMemory / UInt64(bytesPerMb)), diskTotalGb: total / bytesPerGb, diskAvailableGb: Int(available) / bytesPerGb)
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
