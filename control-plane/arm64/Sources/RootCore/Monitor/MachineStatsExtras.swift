import Foundation

/// The optional numbers a helper may add to its answer (docs/monitor-contract.md, section 1). A helper that does not know them leaves them out.
extension MachineStats {
    /// Share of the last interval in each CPU state, in percent. Linux gives all eight, a Mac only user, system, nice and idle.
    public struct Breakdown: Codable, Equatable, Sendable {
        public var user: Double?
        public var system: Double?
        public var nice: Double?
        public var idle: Double?
        public var iowait: Double?
        public var irq: Double?
        public var softirq: Double?
        public var steal: Double?
    }

    /// A group of logical CPUs the system names (Apple Silicon: Performance and Efficiency).
    public struct Cluster: Codable, Equatable, Sendable {
        public var name: String
        public var logical: Int
    }

    public struct Frequency: Codable, Equatable, Sendable {
        public var average: Double
        public var max: Double
    }

    public struct DiskIo: Codable, Equatable, Sendable {
        public var readBytesPerSecond: Double
        public var writeBytesPerSecond: Double
    }
}

extension MachineStats.Breakdown {
    /// A state that is not a share of 0..100 is dropped (left out), never clamped into a number the machine did not give. Nothing left: no breakdown.
    func limited() -> MachineStats.Breakdown? {
        let kept = MachineStats.Breakdown(user: MachineStats.percentOrNil(user), system: MachineStats.percentOrNil(system), nice: MachineStats.percentOrNil(nice),
                                          idle: MachineStats.percentOrNil(idle), iowait: MachineStats.percentOrNil(iowait), irq: MachineStats.percentOrNil(irq),
                                          softirq: MachineStats.percentOrNil(softirq), steal: MachineStats.percentOrNil(steal))
        return kept == MachineStats.Breakdown() ? nil : kept
    }
}

extension MachineStats.Frequency {
    func limited() -> MachineStats.Frequency? {
        let range = 0.0...MachineStats.maxMegahertz
        guard average.isFinite, max.isFinite, average > 0, max > 0, range.contains(average), range.contains(max) else { return nil }
        return self
    }
}

extension MachineStats.DiskIo {
    func limited() -> MachineStats.DiskIo? {
        guard let read = MachineStats.rateOrNil(readBytesPerSecond), let write = MachineStats.rateOrNil(writeBytesPerSecond) else { return nil }
        return .init(readBytesPerSecond: read, writeBytesPerSecond: write)
    }
}

extension MachineStats.Cpu {
    /// One entry per logical CPU, each a core number below the logical count. Anything else: the grouping is not believed and is left out.
    func limitedCoreOf(logical: Int) -> [Int]? {
        guard let coreOf, coreOf.count == logical, coreOf.allSatisfy({ (0..<logical).contains($0) }) else { return nil }
        return coreOf
    }

    func limitedClusters(logical: Int) -> [MachineStats.Cluster]? {
        let kept = (clusters ?? []).prefix(MachineStats.maxClusters).filter { (1...logical).contains($0.logical) }
            .map { MachineStats.Cluster(name: MachineStats.cut($0.name, MachineStats.maxTextCharacters), logical: $0.logical) }
        return kept.isEmpty ? nil : kept
    }
}
