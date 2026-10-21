import Foundation

/// CPU time counters of one logical core. `busy` is everything except idle.
public struct CoreTicks: Equatable {
    public let busy: UInt64
    public let total: UInt64
    public init(busy: UInt64, total: UInt64) { self.busy = busy; self.total = total }
}

public struct MemoryReading: Equatable {
    public let totalBytes, usedBytes, cachedBytes, freeBytes, swapTotalBytes, swapUsedBytes: UInt64
    public init(totalBytes: UInt64, usedBytes: UInt64, cachedBytes: UInt64, freeBytes: UInt64, swapTotalBytes: UInt64, swapUsedBytes: UInt64) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.cachedBytes = cachedBytes; self.freeBytes = freeBytes
        self.swapTotalBytes = swapTotalBytes; self.swapUsedBytes = swapUsedBytes
    }
}

public struct DiskReading: Equatable {
    public let mount, name, fs: String
    public let totalBytes, freeBytes: UInt64
    public init(mount: String, name: String, fs: String, totalBytes: UInt64, freeBytes: UInt64) {
        self.mount = mount; self.name = name; self.fs = fs; self.totalBytes = totalBytes; self.freeBytes = freeBytes
    }
}

/// One program as the system lists it. Deliberately no command line, arguments, environment or open files: the only text is the program name and the user.
public struct RawProcess: Equatable {
    public let pid: Int
    public let name, user: String
    public let cpuNanoseconds, memoryBytes: UInt64
    public init(pid: Int, name: String, user: String, cpuNanoseconds: UInt64, memoryBytes: UInt64) {
        self.pid = pid; self.name = name; self.user = user; self.cpuNanoseconds = cpuNanoseconds; self.memoryBytes = memoryBytes
    }
}

/// Raw counters at one moment. Percentages come from two of these.
public struct StatsSnapshot {
    public let takenAt: Date
    public let uptimeSeconds: Int
    public let cores: [CoreTicks]
    public let load: [Double?]
    public let memory: MemoryReading
    public let disks: [DiskReading]
    public let receivedTotalBytes, sentTotalBytes: UInt64
    public let processes: [RawProcess]
    public init(takenAt: Date, uptimeSeconds: Int, cores: [CoreTicks], load: [Double?], memory: MemoryReading, disks: [DiskReading],
                receivedTotalBytes: UInt64, sentTotalBytes: UInt64, processes: [RawProcess]) {
        self.takenAt = takenAt; self.uptimeSeconds = uptimeSeconds; self.cores = cores; self.load = load; self.memory = memory; self.disks = disks
        self.receivedTotalBytes = receivedTotalBytes; self.sentTotalBytes = sentTotalBytes; self.processes = processes
    }
}

/// Where the numbers come from. The real one reads the system; tests give a fake.
public protocol StatsSource: AnyObject {
    func read() throws -> StatsSnapshot
}
