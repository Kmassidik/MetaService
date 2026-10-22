import Foundation

/// The arithmetic of the sampler: percentages, rates, limits.
enum StatsMath {
    static func build(_ now: StatsSnapshot, since old: StatsSnapshot?) -> MachineStats {
        let seconds = old.map { now.takenAt.timeIntervalSince($0.takenAt) }
        return MachineStats(
            takenAt: timestamp(now.takenAt), measuring: old == nil, uptimeSeconds: now.uptimeSeconds,
            cpu: cpu(now, old), memory: memory(now.memory), disks: now.disks.prefix(StatsSampler.maxDisks).map(disk),
            network: network(now, old, seconds), diskIo: diskIo(now, old, seconds), processCount: now.extras.processCount.map { max(0, $0) }, gpus: gpus(now), processes: processes(now, old, seconds))
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func cpu(_ now: StatsSnapshot, _ old: StatsSnapshot?) -> MachineStats.Cpu {
        let load = MachineStats.Load(one: value(now.load, 0), five: value(now.load, 1), fifteen: value(now.load, 2))
        var answer = MachineStats.Cpu(coreCount: now.cores.count, totalPercent: nil, coresPercent: nil, load: load)
        applyTopology(now, to: &answer)
        guard let old else { return answer }
        let pairs = zip(now.cores, old.cores)
        let busy = pairs.reduce(UInt64(0)) { $0 + delta($1.0.busy, $1.1.busy) }
        let total = pairs.reduce(UInt64(0)) { $0 + delta($1.0.total, $1.1.total) }
        answer = MachineStats.Cpu(coreCount: now.cores.count, totalPercent: ratio(busy, total), coresPercent: pairs.map { percent(busy: $0.busy, $1.busy, total: $0.total, $1.total) }, load: load,
                                  physicalCores: answer.physicalCores, coreOf: answer.coreOf, clusters: answer.clusters, breakdown: breakdown(now.extras.cpuStates, old.extras.cpuStates))
        return answer
    }

    private static func value(_ list: [Double?], _ index: Int) -> Double? {
        guard index < list.count, let number = list[index], number.isFinite, number >= 0 else { return nil }
        return number
    }

    private static func percent(busy new: UInt64, _ old: UInt64, total newTotal: UInt64, _ oldTotal: UInt64) -> Double {
        ratio(delta(new, old), delta(newTotal, oldTotal))
    }

    static func ratio(_ part: UInt64, _ whole: UInt64) -> Double {
        guard whole > 0 else { return 0 }
        return round1(min(100, Double(part) / Double(whole) * 100))
    }

    static func delta(_ new: UInt64, _ old: UInt64) -> UInt64 { new >= old ? new - old : 0 }

    static func round1(_ number: Double) -> Double { (number * 10).rounded() / 10 }

    private static func memory(_ raw: MemoryReading) -> MachineStats.Memory {
        let used = min(raw.usedBytes, raw.totalBytes)
        let cached = min(raw.cachedBytes, raw.totalBytes - used)
        let free = min(raw.freeBytes, raw.totalBytes - used - cached)
        return .init(totalBytes: raw.totalBytes, usedBytes: used, cachedBytes: cached, freeBytes: free, swapTotalBytes: raw.swapTotalBytes, swapUsedBytes: min(raw.swapUsedBytes, raw.swapTotalBytes))
    }

    private static func disk(_ raw: DiskReading) -> MachineStats.Disk {
        let free = min(raw.freeBytes, raw.totalBytes)
        return .init(mount: String(raw.mount.prefix(StatsSampler.maxMountCharacters)), name: String(raw.name.prefix(StatsSampler.maxTextCharacters)),
                     fs: String(raw.fs.prefix(StatsSampler.maxFsCharacters)), totalBytes: raw.totalBytes, usedBytes: raw.totalBytes - free, freeBytes: free)
    }

    private static func network(_ now: StatsSnapshot, _ old: StatsSnapshot?, _ seconds: Double?) -> MachineStats.Network {
        .init(receivedTotalBytes: now.receivedTotalBytes, sentTotalBytes: now.sentTotalBytes,
              receivedBytesPerSecond: rate(now.receivedTotalBytes, old?.receivedTotalBytes, seconds), sentBytesPerSecond: rate(now.sentTotalBytes, old?.sentTotalBytes, seconds),
              errorsInTotal: now.extras.networkIssues?.errorsIn, errorsOutTotal: now.extras.networkIssues?.errorsOut, dropsInTotal: now.extras.networkIssues?.dropsIn)
    }

    /// Bytes per second between two counters; a counter that went backwards (wrap, interface gone) is unknown, not negative.
    static func rate(_ new: UInt64, _ old: UInt64?, _ seconds: Double?) -> Double? {
        guard let old, let seconds, seconds > 0, new >= old else { return nil }
        return round1(Double(new - old) / seconds)
    }

    /// Without a program list in this snapshot the answer has none. Without one in the earlier snapshot there is nothing to compare with: the CPU of each program is unknown, not 0.
    private static func processes(_ now: StatsSnapshot, _ old: StatsSnapshot?, _ seconds: Double?) -> [MachineStats.Process] {
        guard let current = now.processes else { return [] }
        let earlierList = old?.processes
        let before = Dictionary(earlierList?.map { ($0.pid, $0.cpuNanoseconds) } ?? [], uniquingKeysWith: { first, _ in first })
        let comparable = earlierList == nil ? nil : seconds
        let listed = current.map { raw in
            MachineStats.Process(pid: raw.pid, name: String(raw.name.prefix(StatsSampler.maxTextCharacters)), user: String(raw.user.prefix(StatsSampler.maxTextCharacters)),
                                 cpuPercent: comparable.map { cpuPercent(raw, before[raw.pid], $0) }, memoryBytes: raw.memoryBytes, threads: raw.threads.map { max(0, $0) })
        }
        return Array(listed.sorted(by: outranks).prefix(StatsSampler.maxProcesses))
    }

    /// Percent of ONE core. A program that was not listed before, or whose counter went back, counts as 0.
    private static func cpuPercent(_ raw: RawProcess, _ earlier: UInt64?, _ seconds: Double) -> Double {
        guard let earlier else { return 0 }
        let nanos = Double(delta(raw.cpuNanoseconds, earlier))
        return round1(nanos / (seconds * 1_000_000_000) * 100)
    }

    private static func outranks(_ a: MachineStats.Process, _ b: MachineStats.Process) -> Bool {
        let (x, y) = (a.cpuPercent ?? 0, b.cpuPercent ?? 0)
        if x != y { return x > y }
        if a.memoryBytes != b.memoryBytes { return a.memoryBytes > b.memoryBytes }
        return a.pid < b.pid
    }
}
