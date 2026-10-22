import Foundation

/// The GPU part of the answer: names cut, numbers in range, at most eight chips, and nil (not an empty list) when there is none.
extension StatsMath {
    static func gpus(_ now: StatsSnapshot) -> [MachineStats.Gpu]? {
        let listed = now.extras.gpus.prefix(StatsSampler.maxGpus).map { gpu($0, machineMemory: now.memory.totalBytes) }
        return listed.isEmpty ? nil : Array(listed)
    }

    private static func gpu(_ raw: GpuReading, machineMemory: UInt64) -> MachineStats.Gpu {
        let total = raw.sharesSystemMemory && machineMemory > 0 ? machineMemory : nil
        let used = raw.memoryUsedBytes.map { min($0, total ?? $0) }
        return MachineStats.Gpu(name: String(raw.name.prefix(StatsSampler.maxTextCharacters)), vendor: raw.vendor, utilizationPercent: raw.utilizationPercent.map(round1),
                                memoryUsedBytes: used, memoryTotalBytes: total, temperatureCelsius: nil)
    }
}
