import Foundation
import MSCore
import RootCore
import RootStore

/// Writes the per-minute network usage of every machine to the database. The history sampler feeds it every reading it keeps.
/// A finished minute is written as soon as the next minute starts; the minute still being built is written every flush interval, so a restart loses at most that minute.
/// Minutes older than the kept days are deleted once an hour. Failed writes are reported on stderr and the next write tries again.
actor NetUsageCollector {
    /// The old minutes are deleted once an hour, not on every flush.
    static let pruneEverySeconds = 3_600

    private let store: NetMinuteStore
    private let clock: Clock
    private var accumulator = NetMinuteAccumulator()
    /// The epoch second of the last successful delete of old minutes; nil until the first one.
    private var lastPrune: Int?

    init(store: NetMinuteStore, clock: Clock) {
        self.store = store
        self.clock = clock
    }

    /// Adds one reading of a machine (its speeds at the point's time). The finished minute, if any, is written.
    func ingest(machineId: String, point: HistoryPoint) {
        let finished = accumulator.add(machineId: machineId, at: point.t, inBps: point.netInBps, outBps: point.netOutBps)
        write(finished)
    }

    /// Runs one flush every flush interval until the task is cancelled. The sleep ends early only when the task is cancelled, which the loop checks.
    func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(NetUsageRules.flushSeconds))
            flush()
        }
    }

    /// Writes the minutes still being built for every machine, then deletes old minutes when due.
    func flush() {
        write(accumulator.takeOpenMinutes())
        pruneIfDue()
    }

    private func write(_ minutes: [NetMinute]) {
        guard !minutes.isEmpty else { return }
        do {
            try store.record(minutes)
        } catch {
            FileHandle.standardError.write(Data("metaservice-root: network usage write failed: \(error)\n".utf8))
        }
    }

    private func pruneIfDue() {
        let now = Int(clock.now.timeIntervalSince1970)
        guard isPruneDue(now) else { return }
        do {
            try store.deleteOlderThan(minute: cutoffMinute(now))
            lastPrune = now
        } catch {
            FileHandle.standardError.write(Data("metaservice-root: network usage prune failed: \(error)\n".utf8))
        }
    }

    private func isPruneDue(_ now: Int) -> Bool {
        guard let last = lastPrune else { return true }
        return now - last >= Self.pruneEverySeconds
    }

    /// The first minute that is still kept: the minute `keepDays` days before now.
    private func cutoffMinute(_ now: Int) -> Int {
        (now - NetUsageRules.keepDays * NetUsageRules.secondsPerDay) / NetUsageRules.secondsPerMinute
    }
}
