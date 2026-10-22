import Foundation

/// What a helper says about its machine right now (docs/monitor-contract.md, section 1). The parent decodes the helper's answer into this
/// and applies the limits again, so a helper that lies or is attacked cannot make the panel show more than the contract allows.
/// A value the helper could not know is nil, never 0. There is no field for a command line: it cannot be kept.
public struct MachineStats: Codable, Equatable, Sendable {
    public static let maxProcesses = 15
    public static let maxCores = 1024
    public static let maxDisks = 16
    public static let maxGpus = 8
    public static let maxGpuPrograms = 8
    public static let maxTextCharacters = 64
    public static let maxMountCharacters = 128
    public static let maxFsCharacters = 32
    public static let maxTimeCharacters = 32
    public static let maxAnswerBytes = 64 * 1024
    public static let maxClusters = 8
    public static let maxThreads = 1_000_000
    public static let maxProcessCount = 4_194_304
    /// A running total larger than this (2^53, the biggest whole number a browser keeps exactly) is not believed.
    public static let maxCounter = 1 << 53
    public static let maxMegahertz = 20_000.0
    /// Outside this range a temperature is a broken sensor (0 means "no value").
    public static let minCelsius = 1.0
    public static let maxCelsius = 150.0

    public struct Load: Codable, Equatable, Sendable {
        public var one: Double?
        public var five: Double?
        public var fifteen: Double?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(one, forKey: .one)
            try box.encode(five, forKey: .five)
            try box.encode(fifteen, forKey: .fifteen)
        }
    }

    public struct Cpu: Codable, Equatable, Sendable {
        public var coreCount: Int
        public var totalPercent: Double?
        public var coresPercent: [Double]?
        public var load: Load
        /// Optional extras: a helper that does not know them leaves them out, and they stay out of the answer too.
        public var physicalCores: Int?
        public var coreOf: [Int]?
        public var clusters: [Cluster]?
        public var breakdown: Breakdown?
        public var frequencyMhz: Frequency?
        public var temperatureCelsius: Double?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(coreCount, forKey: .coreCount)
            try box.encode(totalPercent, forKey: .totalPercent)
            try box.encode(coresPercent, forKey: .coresPercent)
            try box.encode(load, forKey: .load)
            try box.encodeIfPresent(physicalCores, forKey: .physicalCores)
            try box.encodeIfPresent(coreOf, forKey: .coreOf)
            try box.encodeIfPresent(clusters, forKey: .clusters)
            try box.encodeIfPresent(breakdown, forKey: .breakdown)
            try box.encodeIfPresent(frequencyMhz, forKey: .frequencyMhz)
            try box.encodeIfPresent(temperatureCelsius, forKey: .temperatureCelsius)
        }
    }

    public struct Memory: Codable, Equatable, Sendable {
        public var totalBytes: Int
        public var usedBytes: Int
        public var cachedBytes: Int
        public var freeBytes: Int
        public var swapTotalBytes: Int
        public var swapUsedBytes: Int
    }

    public struct Disk: Codable, Equatable, Sendable {
        public var mount: String
        public var name: String
        public var fs: String
        public var totalBytes: Int
        public var usedBytes: Int
        public var freeBytes: Int
    }

    public struct Network: Codable, Equatable, Sendable {
        public var receivedTotalBytes: Int
        public var sentTotalBytes: Int
        public var receivedBytesPerSecond: Double?
        public var sentBytesPerSecond: Double?
        /// Running totals since boot; the panel shows the change. A Mac gives no drops on the way out.
        public var errorsInTotal: Int?
        public var errorsOutTotal: Int?
        public var dropsInTotal: Int?
        public var dropsOutTotal: Int?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(receivedTotalBytes, forKey: .receivedTotalBytes)
            try box.encode(sentTotalBytes, forKey: .sentTotalBytes)
            try box.encode(receivedBytesPerSecond, forKey: .receivedBytesPerSecond)
            try box.encode(sentBytesPerSecond, forKey: .sentBytesPerSecond)
            try box.encodeIfPresent(errorsInTotal, forKey: .errorsInTotal)
            try box.encodeIfPresent(errorsOutTotal, forKey: .errorsOutTotal)
            try box.encodeIfPresent(dropsInTotal, forKey: .dropsInTotal)
            try box.encodeIfPresent(dropsOutTotal, forKey: .dropsOutTotal)
        }
    }

    public struct Gpu: Codable, Equatable, Sendable {
        public var name: String
        public var utilizationPercent: Double?
        public var memoryUsedBytes: Int?
        public var memoryTotalBytes: Int?
        public var temperatureCelsius: Double?
        /// Optional extras: a helper that cannot read them leaves them out, and they stay out of the answer too (never 0).
        public var vendor: String?
        public var powerWatts: Double?
        public var powerLimitWatts: Double?
        public var fanPercent: Double?
        public var clockMhz: Double?
        public var processes: [GpuProgram]?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(name, forKey: .name)
            try box.encode(utilizationPercent, forKey: .utilizationPercent)
            try box.encode(memoryUsedBytes, forKey: .memoryUsedBytes)
            try box.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
            try box.encode(temperatureCelsius, forKey: .temperatureCelsius)
            try box.encodeIfPresent(vendor, forKey: .vendor)
            try box.encodeIfPresent(powerWatts, forKey: .powerWatts)
            try box.encodeIfPresent(powerLimitWatts, forKey: .powerLimitWatts)
            try box.encodeIfPresent(fanPercent, forKey: .fanPercent)
            try box.encodeIfPresent(clockMhz, forKey: .clockMhz)
            try box.encodeIfPresent(processes, forKey: .processes)
        }
    }

    public struct Process: Codable, Equatable, Sendable {
        public var pid: Int
        public var name: String
        public var user: String
        public var cpuPercent: Double?
        public var memoryBytes: Int
        public var threads: Int?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(pid, forKey: .pid)
            try box.encode(name, forKey: .name)
            try box.encode(user, forKey: .user)
            try box.encode(cpuPercent, forKey: .cpuPercent)
            try box.encode(memoryBytes, forKey: .memoryBytes)
            try box.encodeIfPresent(threads, forKey: .threads)
        }
    }

    public var takenAt: String
    public var measuring: Bool
    public var uptimeSeconds: Int
    public var cpu: Cpu
    public var memory: Memory
    public var disks: [Disk]
    public var network: Network
    /// Left out (nil) when the machine has no safe way to say.
    public var diskIo: DiskIo?
    /// Left out (nil) when the helper does not say. How many programs run, not only the listed ones.
    public var processCount: Int?
    /// Left out (nil) when the machine cannot say. Never an empty list.
    public var gpus: [Gpu]?
    public var processes: [Process]

    private enum CodingKeys: String, CodingKey { case takenAt, measuring, uptimeSeconds, cpu, memory, disks, network, diskIo, processCount, gpus, processes }

    /// Written like the contract: a missing number is null, but the gpus key is left out when there are none.
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(takenAt, forKey: .takenAt)
        try box.encode(measuring, forKey: .measuring)
        try box.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try box.encode(cpu, forKey: .cpu)
        try box.encode(memory, forKey: .memory)
        try box.encode(disks, forKey: .disks)
        try box.encode(network, forKey: .network)
        try box.encodeIfPresent(diskIo, forKey: .diskIo)
        try box.encodeIfPresent(processCount, forKey: .processCount)
        try box.encodeIfPresent(gpus, forKey: .gpus)
        try box.encode(processes, forKey: .processes)
    }
}
