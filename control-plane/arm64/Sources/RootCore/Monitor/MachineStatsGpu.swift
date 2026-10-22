import Foundation

/// A program holding GPU memory (NVIDIA only; a helper that cannot list them leaves `processes` out).
extension MachineStats {
    public struct GpuProgram: Codable, Equatable, Sendable {
        public var name: String
        public var memoryBytes: Int
    }

    /// The makers a helper may name. Any other text is "unknown": the panel shows a fixed chip, never the helper's words.
    public static let gpuVendors: Set<String> = ["nvidia", "amd", "apple", "intel", "unknown"]
    public static let unknownGpuVendor = "unknown"
    public static let maxWatts = 2000.0
    public static let maxFanPercent = 100.0

    static func limitedGpus(_ gpus: [Gpu]?) -> [Gpu]? {
        guard let gpus, !gpus.isEmpty else { return nil }
        return gpus.prefix(maxGpus).map { $0.limited() }
    }
}

extension MachineStats.Gpu {
    /// Every number outside its range is dropped (left out or null), never clamped into a value the machine did not give.
    func limited() -> MachineStats.Gpu {
        .init(name: MachineStats.cut(name, MachineStats.maxTextCharacters), utilizationPercent: MachineStats.percentOrNil(utilizationPercent),
              memoryUsedBytes: memoryUsedBytes.flatMap(MachineStats.countOrNil), memoryTotalBytes: memoryTotalBytes.flatMap(MachineStats.countOrNil),
              temperatureCelsius: MachineStats.rangeOrNil(temperatureCelsius, MachineStats.minCelsius...MachineStats.maxCelsius),
              vendor: vendor.map { MachineStats.gpuVendors.contains($0) ? $0 : MachineStats.unknownGpuVendor },
              powerWatts: MachineStats.rangeOrNil(powerWatts, 0...MachineStats.maxWatts), powerLimitWatts: MachineStats.rangeOrNil(powerLimitWatts, 0...MachineStats.maxWatts),
              fanPercent: MachineStats.rangeOrNil(fanPercent, 0...MachineStats.maxFanPercent), clockMhz: MachineStats.rangeOrNil(clockMhz, 1...MachineStats.maxMegahertz),
              processes: processes.map(limitedPrograms))
    }

    private func limitedPrograms(_ programs: [MachineStats.GpuProgram]) -> [MachineStats.GpuProgram] {
        programs.prefix(MachineStats.maxGpuPrograms).compactMap { program in
            MachineStats.countOrNil(program.memoryBytes).map { MachineStats.GpuProgram(name: MachineStats.cut(program.name, MachineStats.maxTextCharacters), memoryBytes: $0) }
        }
    }
}
