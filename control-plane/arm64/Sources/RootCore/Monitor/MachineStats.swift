import Foundation

/// What a helper says about its machine right now (docs/monitor-contract.md, section 1). The parent decodes the helper's answer into this
/// and applies the limits again, so a helper that lies or is attacked cannot make the panel show more than the contract allows.
/// A value the helper could not know is nil, never 0. There is no field for a command line: it cannot be kept.
public struct MachineStats: Codable, Equatable, Sendable {
    public static let maxProcesses = 15
    public static let maxCores = 1024
    public static let maxDisks = 16
    public static let maxGpus = 16
    public static let maxTextCharacters = 64
    public static let maxMountCharacters = 128
    public static let maxFsCharacters = 32
    public static let maxTimeCharacters = 32
    public static let maxAnswerBytes = 64 * 1024

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

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(coreCount, forKey: .coreCount)
            try box.encode(totalPercent, forKey: .totalPercent)
            try box.encode(coresPercent, forKey: .coresPercent)
            try box.encode(load, forKey: .load)
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

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(receivedTotalBytes, forKey: .receivedTotalBytes)
            try box.encode(sentTotalBytes, forKey: .sentTotalBytes)
            try box.encode(receivedBytesPerSecond, forKey: .receivedBytesPerSecond)
            try box.encode(sentBytesPerSecond, forKey: .sentBytesPerSecond)
        }
    }

    public struct Gpu: Codable, Equatable, Sendable {
        public var name: String
        public var utilizationPercent: Double?
        public var memoryUsedBytes: Int?
        public var memoryTotalBytes: Int?
        public var temperatureCelsius: Double?

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(name, forKey: .name)
            try box.encode(utilizationPercent, forKey: .utilizationPercent)
            try box.encode(memoryUsedBytes, forKey: .memoryUsedBytes)
            try box.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
            try box.encode(temperatureCelsius, forKey: .temperatureCelsius)
        }
    }

    public struct Process: Codable, Equatable, Sendable {
        public var pid: Int
        public var name: String
        public var user: String
        public var cpuPercent: Double?
        public var memoryBytes: Int

        public func encode(to encoder: Encoder) throws {
            var box = encoder.container(keyedBy: CodingKeys.self)
            try box.encode(pid, forKey: .pid)
            try box.encode(name, forKey: .name)
            try box.encode(user, forKey: .user)
            try box.encode(cpuPercent, forKey: .cpuPercent)
            try box.encode(memoryBytes, forKey: .memoryBytes)
        }
    }

    public var takenAt: String
    public var measuring: Bool
    public var uptimeSeconds: Int
    public var cpu: Cpu
    public var memory: Memory
    public var disks: [Disk]
    public var network: Network
    /// Left out (nil) when the machine cannot say. Never an empty list.
    public var gpus: [Gpu]?
    public var processes: [Process]

    private enum CodingKeys: String, CodingKey { case takenAt, measuring, uptimeSeconds, cpu, memory, disks, network, gpus, processes }

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
        try box.encodeIfPresent(gpus, forKey: .gpus)
        try box.encode(processes, forKey: .processes)
    }
}
