import Foundation

/// The answer of `GET /v1/stats` (docs/monitor-contract.md). A value that cannot be known yet is encoded as null, never 0.
public struct MachineStats: Equatable {
    public struct Load: Equatable { public let one, five, fifteen: Double? }
    public struct Cpu: Equatable {
        public let coreCount: Int
        public let totalPercent: Double?
        public let coresPercent: [Double]?
        public let load: Load
    }
    public struct Memory: Equatable { public let totalBytes, usedBytes, cachedBytes, freeBytes, swapTotalBytes, swapUsedBytes: UInt64 }
    public struct Disk: Equatable { public let mount, name, fs: String; public let totalBytes, usedBytes, freeBytes: UInt64 }
    public struct Network: Equatable {
        public let receivedTotalBytes, sentTotalBytes: UInt64
        public let receivedBytesPerSecond, sentBytesPerSecond: Double?
    }
    public struct Gpu: Equatable {
        public let name: String
        public let utilizationPercent: Double?
        public let memoryUsedBytes, memoryTotalBytes: UInt64?
        public let temperatureCelsius: Double?
    }
    public struct Process: Equatable { public let pid: Int; public let name, user: String; public let cpuPercent: Double?; public let memoryBytes: UInt64 }

    public let takenAt: String
    public let measuring: Bool
    public let uptimeSeconds: Int
    public let cpu: Cpu
    public let memory: Memory
    public let disks: [Disk]
    public let network: Network
    /// Left out (nil) when the system cannot say. A Mac never says without root.
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
    private enum Keys: String, CodingKey { case coreCount, totalPercent, coresPercent, load }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(coreCount, forKey: .coreCount); try box.encode(totalPercent, forKey: .totalPercent)
        try box.encode(coresPercent, forKey: .coresPercent); try box.encode(load, forKey: .load)
    }
}

extension MachineStats.Network: Encodable {
    private enum Keys: String, CodingKey { case receivedTotalBytes, sentTotalBytes, receivedBytesPerSecond, sentBytesPerSecond }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(receivedTotalBytes, forKey: .receivedTotalBytes); try box.encode(sentTotalBytes, forKey: .sentTotalBytes)
        try box.encode(receivedBytesPerSecond, forKey: .receivedBytesPerSecond); try box.encode(sentBytesPerSecond, forKey: .sentBytesPerSecond)
    }
}

extension MachineStats.Process: Encodable {
    private enum Keys: String, CodingKey { case pid, name, user, cpuPercent, memoryBytes }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(pid, forKey: .pid); try box.encode(name, forKey: .name); try box.encode(user, forKey: .user)
        try box.encode(cpuPercent, forKey: .cpuPercent); try box.encode(memoryBytes, forKey: .memoryBytes)
    }
}

extension MachineStats.Gpu: Encodable {
    private enum Keys: String, CodingKey { case name, utilizationPercent, memoryUsedBytes, memoryTotalBytes, temperatureCelsius }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: Keys.self)
        try box.encode(name, forKey: .name); try box.encode(utilizationPercent, forKey: .utilizationPercent)
        try box.encode(memoryUsedBytes, forKey: .memoryUsedBytes); try box.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
        try box.encode(temperatureCelsius, forKey: .temperatureCelsius)
    }
}

extension MachineStats: Encodable {}
extension MachineStats.Memory: Encodable {}
extension MachineStats.Disk: Encodable {}

public enum StatsJson {
    public static func encode(_ stats: MachineStats) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(stats)
    }
}
