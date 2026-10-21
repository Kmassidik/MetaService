import Foundation

/// Turns two raw snapshots into the numbers the page shows. Pure: all system access is behind `StatsSource`.
public final class StatsSampler: @unchecked Sendable {
    public static let maxProcesses = 15
    public static let maxDisks = 16
    public static let maxTextCharacters = 64
    public static let maxMountCharacters = 128
    public static let maxFsCharacters = 32
    /// An earlier sample older than this is not compared with.
    public static let staleAfterSeconds: Double = 60

    private let source: StatsSource
    private let lock = NSLock()
    private var previous: StatsSnapshot?

    public init(source: StatsSource) { self.source = source }

    /// `includeProcesses` false: the programs are not scanned and the answer has an empty list.
    public func sample(includeProcesses: Bool = true) throws -> MachineStats {
        lock.lock(); defer { lock.unlock() }
        let now = try source.read(includeProcesses: includeProcesses)
        let earlier = comparable(previous, now)
        previous = now
        return StatsMath.build(now, since: earlier)
    }

    private func comparable(_ old: StatsSnapshot?, _ new: StatsSnapshot) -> StatsSnapshot? {
        guard let old else { return nil }
        let seconds = new.takenAt.timeIntervalSince(old.takenAt)
        guard seconds > 0, seconds <= Self.staleAfterSeconds, old.cores.count == new.cores.count else { return nil }
        return old
    }
}
