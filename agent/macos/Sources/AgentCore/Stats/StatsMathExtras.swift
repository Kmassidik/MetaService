import Foundation

/// The optional numbers: CPU layout, CPU states, disk speed. Each is left out when the system does not give it.
extension StatsMath {
    /// Physical core count, which logical CPU belongs to which core, and the clusters the system names.
    static func applyTopology(_ now: StatsSnapshot, to cpu: inout MachineStats.Cpu) {
        guard let topology = now.extras.topology, topology.physicalCores > 0 else { return }
        cpu.physicalCores = min(topology.physicalCores, now.cores.count)
        cpu.coreOf = coreOf(logical: now.cores.count, physical: topology.physicalCores)
        let clusters = topology.clusters.filter { $0.logical > 0 }
        cpu.clusters = clusters.isEmpty ? nil : clusters.map { MachineStats.Cluster(name: String($0.name.prefix(StatsSampler.maxTextCharacters)), logical: $0.logical) }
    }

    /// One core per CPU when there are as many cores as CPUs (Apple Silicon: no hyper-threading). With hyper-threading (Intel Macs) the threads of a core are taken to sit next to each other in the system's list (not verified on real Intel hardware). A count that does not divide evenly is not known, so left out.
    static func coreOf(logical: Int, physical: Int) -> [Int]? {
        guard logical > 0, physical > 0, physical <= logical, logical % physical == 0 else { return nil }
        let threadsPerCore = logical / physical
        return (0..<logical).map { $0 / threadsPerCore }
    }

    /// Share of each state in the gap between two readings. Nothing to compare with, or no time passed: left out.
    static func breakdown(_ now: CpuStateTicks?, _ old: CpuStateTicks?) -> MachineStats.Breakdown? {
        guard let now, let old else { return nil }
        let (user, system, nice, idle) = (delta(now.user, old.user), delta(now.system, old.system), delta(now.nice, old.nice), delta(now.idle, old.idle))
        let total = user + system + nice + idle
        guard total > 0 else { return nil }
        return .init(user: ratio(user, total), system: ratio(system, total), nice: ratio(nice, total), idle: ratio(idle, total))
    }

    /// Read and write speed between two readings; either counter going backwards makes the pair unknown.
    static func diskIo(_ now: StatsSnapshot, _ old: StatsSnapshot?, _ seconds: Double?) -> MachineStats.DiskIo? {
        guard let new = now.extras.diskTotals, let before = old?.extras.diskTotals,
              let read = rate(new.readBytes, before.readBytes, seconds), let written = rate(new.writtenBytes, before.writtenBytes, seconds) else { return nil }
        return .init(readBytesPerSecond: read, writeBytesPerSecond: written)
    }
}
