import Foundation

/// The answer of `GET /v1/stats` (docs/monitor-contract.md). A value that cannot be known yet is encoded as null, never 0.
public struct MachineStats: Equatable {
    public struct Load: Equatable { public let one, five, fifteen: Double? }
    public struct Cpu: Equatable {
        public let coreCount: Int
        public let totalPercent: Double?
        public let coresPercent: [Double]?
        public let load: Load
        /// Physical cores (`coreCount` is the logical count). Left out when unknown.
        public var physicalCores: Int?
        /// For each logical CPU, the index of its physical core.
        public var coreOf: [Int]?
        public var clusters: [Cluster]?
        /// Share of the last interval in each state. user, system, nice, idle only: a Mac gives no more.
        public var breakdown: Breakdown?
    }
    public struct Cluster: Equatable { public let name: String; public let logical: Int }
    public struct Breakdown: Equatable { public let user, system, nice, idle: Double }
    public struct DiskIo: Equatable { public let readBytesPerSecond, writeBytesPerSecond: Double }
    public struct Memory: Equatable { public let totalBytes, usedBytes, cachedBytes, freeBytes, swapTotalBytes, swapUsedBytes: UInt64 }
    public struct Disk: Equatable { public let mount, name, fs: String; public let totalBytes, usedBytes, freeBytes: UInt64 }
    public struct Network: Equatable {
        public let receivedTotalBytes, sentTotalBytes: UInt64
        public let receivedBytesPerSecond, sentBytesPerSecond: Double?
        public var errorsInTotal, errorsOutTotal, dropsInTotal: UInt64?
    }
    public struct Gpu: Equatable {
        public let name: String
        /// "nvidia", "amd", "apple", "intel" or "unknown". A Mac says "apple" (use and memory only: temperature, power and clock need root).
        public let vendor: String
        public let utilizationPercent: Double?
        public let memoryUsedBytes, memoryTotalBytes: UInt64?
        public let temperatureCelsius: Double?
    }
    public struct Process: Equatable { public let pid: Int; public let name, user: String; public let cpuPercent: Double?; public let memoryBytes: UInt64; public var threads: Int? = nil }

    public let takenAt: String
    public let measuring: Bool
    public let uptimeSeconds: Int
    public let cpu: Cpu
    public let memory: Memory
    public let disks: [Disk]
    public let network: Network
    /// Left out (nil) when there is no safe source or nothing to compare with yet.
    public var diskIo: DiskIo?
    /// How many programs run, all users. Left out when the system does not say.
    public var processCount: Int?
    /// Left out (nil) when there is no GPU the system can read.
    public let gpus: [Gpu]?
    public let processes: [Process]
}

extension MachineStats.Load: Encodable {
    private enum Keys: String, CodingKey { case one, five, fifteen }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(one, forKey: .one); try box.encode(five, forKey: .five); try box.encode(fifteen, forKey: .fifteen)
    }
}

extension MachineStats.Cpu: Encodable {
    private enum Keys: String, CodingKey { case coreCount, totalPercent, coresPercent, load, physicalCores, coreOf, clusters, breakdown }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(coreCount, forKey: .coreCount); try box.encode(totalPercent, forKey: .totalPercent)
        try box.encode(coresPercent, forKey: .coresPercent); try box.encode(load, forKey: .load)
        try box.encodeIfPresent(physicalCores, forKey: .physicalCores); try box.encodeIfPresent(coreOf, forKey: .coreOf)
        try box.encodeIfPresent(clusters, forKey: .clusters); try box.encodeIfPresent(breakdown, forKey: .breakdown)
    }
}

extension MachineStats.Network: Encodable {
    private enum Keys: String, CodingKey { case receivedTotalBytes, sentTotalBytes, receivedBytesPerSecond, sentBytesPerSecond, errorsInTotal, errorsOutTotal, dropsInTotal }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(receivedTotalBytes, forKey: .receivedTotalBytes); try box.encode(sentTotalBytes, forKey: .sentTotalBytes)
        try box.encode(receivedBytesPerSecond, forKey: .receivedBytesPerSecond); try box.encode(sentBytesPerSecond, forKey: .sentBytesPerSecond)
        try box.encodeIfPresent(errorsInTotal, forKey: .errorsInTotal); try box.encodeIfPresent(errorsOutTotal, forKey: .errorsOutTotal)
        try box.encodeIfPresent(dropsInTotal, forKey: .dropsInTotal)
    }
}

extension MachineStats.Process: Encodable {
    private enum Keys: String, CodingKey { case pid, name, user, cpuPercent, memoryBytes, threads }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(pid, forKey: .pid); try box.encode(name, forKey: .name); try box.encode(user, forKey: .user)
        try box.encode(cpuPercent, forKey: .cpuPercent); try box.encode(memoryBytes, forKey: .memoryBytes)
        try box.encodeIfPresent(threads, forKey: .threads)
    }
}

extension MachineStats.Gpu: Encodable {
    private enum Keys: String, CodingKey { case name, vendor, utilizationPercent, memoryUsedBytes, memoryTotalBytes, temperatureCelsius }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(name, forKey: .name); try box.encode(vendor, forKey: .vendor); try box.encode(utilizationPercent, forKey: .utilizationPercent)
        try box.encode(memoryUsedBytes, forKey: .memoryUsedBytes); try box.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
        try box.encode(temperatureCelsius, forKey: .temperatureCelsius)
    }
}

extension MachineStats: Encodable {
    private enum Keys: String, CodingKey { case takenAt, measuring, uptimeSeconds, cpu, memory, disks, network, diskIo, processCount, gpus, processes }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(takenAt, forKey: .takenAt); try box.encode(measuring, forKey: .measuring); try box.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try box.encode(cpu, forKey: .cpu); try box.encode(memory, forKey: .memory); try box.encode(disks, forKey: .disks); try box.encode(network, forKey: .network)
        try box.encodeIfPresent(diskIo, forKey: .diskIo); try box.encodeIfPresent(processCount, forKey: .processCount); try box.encodeIfPresent(gpus, forKey: .gpus); try box.encode(processes, forKey: .processes)
    }
}
extension MachineStats.Cluster: Encodable {}
extension MachineStats.Breakdown: Encodable {}
extension MachineStats.DiskIo: Encodable {}
extension MachineStats.Memory: Encodable {}
extension MachineStats.Disk: Encodable {}

public enum StatsJson {
    public static func encode(_ stats: MachineStats) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(stats)
    }
}
