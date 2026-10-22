import Darwin
import Foundation
import AgentCore

/// Physical and logical CPU counts and, on Apple Silicon, the performance levels the kernel names (Performance, Efficiency). No root needed.
enum DarwinTopology {
    private static let namedLevelsNeeded = 2

    static func read() -> CpuTopology? {
        guard let physical = int("hw.physicalcpu"), physical > 0 else { return nil }
        return CpuTopology(physicalCores: physical, clusters: clusters())
    }

    /// Only when the machine has two or more levels: one level is just "all CPUs".
    private static func clusters() -> [CpuCluster] {
        guard let levels = int("hw.nperflevels"), levels >= namedLevelsNeeded else { return [] }
        return (0..<levels).compactMap { level in
            guard let name = text("hw.perflevel\(level).name"), let logical = int("hw.perflevel\(level).logicalcpu") else { return nil }
            return CpuCluster(name: name, logical: logical)
        }
    }

    private static func int(_ name: String) -> Int? {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private static func text(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
