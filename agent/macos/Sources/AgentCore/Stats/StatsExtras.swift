import Foundation

/// CPU time spent in each state, added over all cores, since boot. A Mac gives only these four (host_cpu_load_info): the others are left out of the answer, never 0.
public struct CpuStateTicks: Equatable {
    public let user, system, nice, idle: UInt64
    public init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) { self.user = user; self.system = system; self.nice = nice; self.idle = idle }
}

/// A group of logical CPUs the system names (Apple Silicon: Performance and Efficiency).
public struct CpuCluster: Equatable {
    public let name: String
    public let logical: Int
    public init(name: String, logical: Int) { self.name = name; self.logical = logical }
}

public struct CpuTopology: Equatable {
    public let physicalCores: Int
    public let clusters: [CpuCluster]
    public init(physicalCores: Int, clusters: [CpuCluster]) { self.physicalCores = physicalCores; self.clusters = clusters }
}

/// Packets that failed or were dropped, all interfaces except loopback, since boot. A Mac counts dropped packets on the way in only.
public struct NetworkIssues: Equatable {
    public let errorsIn, errorsOut, dropsIn: UInt64
    public init(errorsIn: UInt64, errorsOut: UInt64, dropsIn: UInt64) { self.errorsIn = errorsIn; self.errorsOut = errorsOut; self.dropsIn = dropsIn }
}

/// Bytes read from and written to the machine's storage devices since boot.
public struct DiskTotals: Equatable {
    public let readBytes, writtenBytes: UInt64
    public init(readBytes: UInt64, writtenBytes: UInt64) { self.readBytes = readBytes; self.writtenBytes = writtenBytes }
}

/// The optional numbers of a snapshot. Each one is nil where the system does not give it without root.
public struct StatsExtras: Equatable {
    public var cpuStates: CpuStateTicks?
    public var topology: CpuTopology?
    public var networkIssues: NetworkIssues?
    public var diskTotals: DiskTotals?
    /// How many programs run, all users (the list in the answer holds only the busiest).
    public var processCount: Int?
    /// The graphics chips the registry shows. Empty when it shows none.
    public var gpus: [GpuReading]
    public init(cpuStates: CpuStateTicks? = nil, topology: CpuTopology? = nil, networkIssues: NetworkIssues? = nil, diskTotals: DiskTotals? = nil, processCount: Int? = nil, gpus: [GpuReading] = []) {
        self.cpuStates = cpuStates; self.topology = topology; self.networkIssues = networkIssues; self.diskTotals = diskTotals; self.processCount = processCount; self.gpus = gpus
    }
}
