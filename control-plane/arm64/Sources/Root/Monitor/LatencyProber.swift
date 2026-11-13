import Foundation
import MSCore
import RootCore
import RootStore

/// The real connector: times one `GET /v1/health` call to the machine's helper through `AgentClient`, the same path the other helper calls use.
/// A reply that is not a success, or a call that throws, gives nil; the error is reported on stderr.
struct AgentHealthConnector: LatencyConnector {
    let client: AgentClient

    static let healthMethod = "GET"
    static let healthPath = "/v1/health"
    private static let minimumMillis = 1
    private static let successStatuses = 200..<300

    func answerMillis(for target: LatencyTarget, timeout: TimeInterval) async -> Int? {
        let started = DispatchTime.now().uptimeNanoseconds
        do {
            let reply = try await client.call(machine: target.machineId, method: Self.healthMethod, path: Self.healthPath, timeout: timeout)
            guard Self.successStatuses.contains(reply.status) else { return nil }
            return Self.millis(since: started)
        } catch {
            FileHandle.standardError.write(Data("metaservice-root: latency probe of \(target.machineId) failed: \(error)\n".utf8))
            return nil
        }
    }

    /// Elapsed milliseconds, rounded up, and never less than one so a fast call is not reported as zero.
    private static func millis(since started: UInt64) -> Int {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let rounded = (elapsed + LatencyTiming.nanosecondsPerMillisecond - 1) / LatencyTiming.nanosecondsPerMillisecond
        return max(Int(rounded), minimumMillis)
    }
}

/// The machines to probe: every registered machine that has an address and a helper port. A machine that looks offline is still probed, because a failed probe is a result.
enum LatencyTargets {
    static func current(_ machines: MachineStore, now: Date) throws -> [LatencyTarget] {
        try machines.list(now: now).compactMap { summary in
            guard let endpoint = try machines.endpoint(id: summary.id) else { return nil }
            return LatencyTarget(machineId: summary.id, host: endpoint.ip, port: endpoint.port)
        }
    }
}

/// Times a health call to every registered machine's helper every ten seconds and stores one sample per machine. One loop for all machines; it stops when the task is cancelled.
/// Old samples are deleted once an hour. The clock and the connector are passed in, so a test can fake them.
actor LatencyProber {
    private let machines: MachineStore
    private let store: LatencyStore
    private let connector: LatencyConnector
    private let clock: Clock
    /// The epoch second of the last delete of old samples; nil until the first one.
    private var lastPrune: Int?

    init(machines: MachineStore, store: LatencyStore, connector: LatencyConnector, clock: Clock) {
        self.machines = machines
        self.store = store
        self.connector = connector
        self.clock = clock
    }

    /// Runs one pass every interval, measured from the start of each pass, until the task is cancelled.
    func run() async {
        let interval = Duration.seconds(LatencyTiming.intervalSeconds)
        while !Task.isCancelled {
            let started = ContinuousClock.now
            await pass()
            let rest = interval - (ContinuousClock.now - started)
            try? await Task.sleep(for: max(rest, .zero))
        }
    }

    /// One pass: probe every target at the same time, store the samples, and delete old ones when due. A failure is reported and the next pass tries again.
    func pass() async {
        let now = Int(clock.now.timeIntervalSince1970)
        do {
            let targets = try LatencyTargets.current(machines, now: clock.now)
            let samples = await LatencyRound.run(targets, at: now, connector: connector, timeout: LatencyTiming.answerTimeoutSeconds)
            try store.record(samples)
            try pruneIfDue(now)
        } catch {
            FileHandle.standardError.write(Data("metaservice-root: latency pass failed: \(error)\n".utf8))
        }
    }

    private func pruneIfDue(_ now: Int) throws {
        guard isPruneDue(now) else { return }
        try store.deleteOlderThan(now - LatencyTiming.keepDays * LatencyTiming.secondsPerDay)
        lastPrune = now
    }

    private func isPruneDue(_ now: Int) -> Bool {
        guard let last = lastPrune else { return true }
        return now - last >= LatencyTiming.pruneEverySeconds
    }
}
