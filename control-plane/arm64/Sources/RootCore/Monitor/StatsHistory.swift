import Foundation

/// The last hour of readings of each machine, kept in memory only (never in the database; gone when the parent restarts).
/// Bounded twice: `capacity` points per machine and `maxMachines` machines, so the memory use has a fixed ceiling.
public struct StatsHistory: Sendable {
    public static let intervalSeconds = 10
    /// One hour at one point per ten seconds.
    public static let capacity = 360
    public static let maxMachines = 256

    private var rings: [String: [HistoryPoint]] = [:]
    private let capacity: Int
    private let maxMachines: Int

    public init(capacity: Int = StatsHistory.capacity, maxMachines: Int = StatsHistory.maxMachines) {
        self.capacity = capacity
        self.maxMachines = maxMachines
    }

    public var machineCount: Int { rings.count }

    /// Adds a point, newest last. A point not newer than the last one is ignored (the same shared reading must not be counted twice).
    /// A machine beyond the limit is not kept: `false`.
    @discardableResult
    public mutating func record(_ id: String, _ point: HistoryPoint) -> Bool {
        guard rings[id] != nil || rings.count < maxMachines else { return false }
        var ring = rings[id] ?? []
        guard ring.last.map({ point.t > $0.t }) ?? true else { return true }
        ring.append(point)
        if ring.count > capacity { ring.removeFirst(ring.count - capacity) }
        rings[id] = ring
        return true
    }

    /// The newest `count` points of a machine, oldest first. Nothing known: empty.
    public func points(_ id: String, last count: Int) -> [HistoryPoint] {
        Array((rings[id] ?? []).suffix(max(count, 0)))
    }

    /// Forgets the machines that are no longer in the list (removed by the operator).
    public mutating func keepOnly(_ ids: Set<String>) {
        rings = rings.filter { ids.contains($0.key) }
    }
}
