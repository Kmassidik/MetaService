import Foundation

/// One reading of a machine kept in the parent's short history (docs/monitor-contract.md, section 2b): the numbers the charts draw, without the process list.
/// Keys are written snake_case (`cpu_percent`, `mem_used`, `net_in_bps`). Optional numbers are left out when the helper did not give them; the two network speeds are null when unknown.
public struct HistoryPoint: Codable, Equatable, Sendable {
    /// Seconds since 1970 when the parent got this reading.
    public var t: Int
    public var cpuPercent: Double
    public var cpuBreakdown: MachineStats.Breakdown?
    /// One, five and fifteen minute load average; left out when the system cannot say all three.
    public var load: [Double]?
    public var memUsed: Int
    public var memCached: Int
    public var memTotal: Int
    public var swapUsed: Int
    public var swapTotal: Int
    public var diskRead: Double?
    public var diskWrite: Double?
    public var netInBps: Double?
    public var netOutBps: Double?
    /// Packets dropped since boot, in and out added (a running total; the panel shows the change).
    public var netDrops: Int?
    public var processesCount: Int?
    /// Per-GPU numbers; left out when the machine has no GPU with a number this time.
    public var gpus: [HistoryGpu]?

    private enum CodingKeys: String, CodingKey {
        case t, cpuPercent, cpuBreakdown, load, memUsed, memCached, memTotal, swapUsed, swapTotal, diskRead, diskWrite, netInBps, netOutBps, netDrops, processesCount, gpus
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(t, forKey: .t)
        try box.encode(cpuPercent, forKey: .cpuPercent)
        try box.encodeIfPresent(cpuBreakdown, forKey: .cpuBreakdown)
        try box.encodeIfPresent(load, forKey: .load)
        try box.encode(memUsed, forKey: .memUsed)
        try box.encode(memCached, forKey: .memCached)
        try box.encode(memTotal, forKey: .memTotal)
        try box.encode(swapUsed, forKey: .swapUsed)
        try box.encode(swapTotal, forKey: .swapTotal)
        try box.encodeIfPresent(diskRead, forKey: .diskRead)
        try box.encodeIfPresent(diskWrite, forKey: .diskWrite)
        try box.encode(netInBps, forKey: .netInBps)
        try box.encode(netOutBps, forKey: .netOutBps)
        try box.encodeIfPresent(netDrops, forKey: .netDrops)
        try box.encodeIfPresent(processesCount, forKey: .processesCount)
        try box.encodeIfPresent(gpus, forKey: .gpus)
    }
}

extension HistoryPoint {
    /// The point for a reading. A reading with no CPU percent yet (the helper is still measuring) makes no point: a gap is truer than a 0.
    public init?(stats: MachineStats, at date: Date) {
        guard let cpu = stats.cpu.totalPercent else { return nil }
        self.init(t: Int(date.timeIntervalSince1970), cpuPercent: cpu, cpuBreakdown: stats.cpu.breakdown, load: Self.load(stats.cpu.load),
                  memUsed: stats.memory.usedBytes, memCached: stats.memory.cachedBytes, memTotal: stats.memory.totalBytes,
                  swapUsed: stats.memory.swapUsedBytes, swapTotal: stats.memory.swapTotalBytes,
                  diskRead: stats.diskIo?.readBytesPerSecond, diskWrite: stats.diskIo?.writeBytesPerSecond,
                  netInBps: stats.network.receivedBytesPerSecond, netOutBps: stats.network.sentBytesPerSecond,
                  netDrops: Self.drops(stats.network), processesCount: stats.processCount, gpus: Self.gpuSeries(stats.gpus))
    }

    private static func load(_ load: MachineStats.Load) -> [Double]? {
        guard let one = load.one, let five = load.five, let fifteen = load.fifteen else { return nil }
        return [one, five, fifteen]
    }

    private static func drops(_ network: MachineStats.Network) -> Int? {
        guard network.dropsInTotal != nil || network.dropsOutTotal != nil else { return nil }
        return (network.dropsInTotal ?? 0) + (network.dropsOutTotal ?? 0)
    }
}
