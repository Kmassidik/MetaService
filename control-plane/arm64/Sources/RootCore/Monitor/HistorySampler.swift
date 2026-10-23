import Foundation
import MSCore

/// A machine as the sampler sees it: its name and whether the parent hears from it now.
public struct SampledMachine: Equatable, Sendable {
    public let id: String
    public let online: Bool

    public init(id: String, online: Bool) {
        self.id = id
        self.online = online
    }
}

/// Where the sampler gets its machines and readings. The real one goes through the shared reading (so the sampler and a person watching together
/// never call a helper more than once per 1.5 seconds); a test gives a fake.
public protocol HistorySource: Sendable {
    func machines() async -> [SampledMachine]
    /// A good reading without the process list and when the parent got it, or nil when the helper did not answer.
    func reading(of id: String) async -> (stats: MachineStats, at: Date)?
}

/// Keeps the last hour of every online machine, one reading each ten seconds, in memory.
/// One loop for all machines (no thread each): each pass asks the machines that are due, at the same time, and records what came back.
public actor HistorySampler {
    private let source: HistorySource
    private let clock: Clock
    private var schedule: HistorySchedule
    private var history: StatsHistory
    private let passSeconds: TimeInterval

    public init(source: HistorySource, clock: Clock, intervalSeconds: Int = StatsHistory.intervalSeconds, history: StatsHistory = StatsHistory()) {
        self.source = source
        self.clock = clock
        self.schedule = HistorySchedule(intervalSeconds: intervalSeconds)
        self.history = history
        self.passSeconds = min(max(TimeInterval(intervalSeconds) / 4, Self.shortestPassSeconds), Self.longestPassSeconds)
    }

    static let shortestPassSeconds: TimeInterval = 0.25
    static let longestPassSeconds: TimeInterval = 1

    /// The newest `count` points of a machine, oldest first. Offline machines keep what they had.
    public func points(_ id: String, last count: Int) -> [HistoryPoint] {
        history.points(id, last: count)
    }

    public var machineCount: Int { history.machineCount }

    /// Runs until the task is cancelled.
    public func run() async {
        while !Task.isCancelled {
            await pass()
            try? await Task.sleep(nanoseconds: UInt64(passSeconds * 1_000_000_000))
        }
    }

    /// One pass: forget removed machines, ask the online machines that are due, record the answers.
    public func pass() async {
        let machines = await source.machines()
        history.keepOnly(Set(machines.map(\.id)))
        let due = schedule.due(online: machines.filter(\.online).map(\.id), now: clock.now)
        let source = self.source
        let answers = await withTaskGroup(of: (String, HistoryPoint?).self) { group -> [(String, HistoryPoint?)] in
            for id in due {
                group.addTask { (id, await source.reading(of: id).flatMap { HistoryPoint(stats: $0.stats, at: $0.at) }) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        for case let (id, point?) in answers { history.record(id, point) }
    }
}
