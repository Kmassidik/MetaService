import Foundation
import MSCore
import Network
import RootCore
import RootStore

/// The real connector: a TCP connection through Network.framework, timed from the start until the connection is ready. It is closed at once and sends no data.
struct TcpLatencyConnector: LatencyConnector {
    private static let queue = DispatchQueue(label: "metaservice.latency.connect")
    private static let minimumMillis = 1

    func connectMillis(host: String, port: Int, timeout: TimeInterval) async -> Int? {
        guard (1...Int(UInt16.max)).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        let started = DispatchTime.now().uptimeNanoseconds
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let once = OnceResult(continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            connection.stateUpdateHandler = { [weak connection] state in
                switch state {
                case .ready:
                    once.finish(Self.millis(since: started))
                    connection?.cancel()
                case .failed, .cancelled:
                    once.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: Self.queue)
            Self.queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                once.finish(nil)
            }
        }
    }

    /// Elapsed milliseconds, rounded up, and never less than one so a fast connection is not reported as zero.
    private static func millis(since started: UInt64) -> Int {
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let rounded = (elapsed + LatencyTiming.nanosecondsPerMillisecond - 1) / LatencyTiming.nanosecondsPerMillisecond
        return max(Int(rounded), minimumMillis)
    }
}

/// Hands back the connect result exactly once, whichever comes first: the ready state, a failure, or the timeout.
private final class OnceResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?

    init(_ continuation: CheckedContinuation<Int?, Never>) { self.continuation = continuation }

    func finish(_ millis: Int?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: millis)
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

/// Probes every registered machine's helper port every ten seconds and stores one sample per machine. One loop for all machines; it stops when the task is cancelled.
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
            let samples = await LatencyRound.run(targets, at: now, connector: connector, timeout: LatencyTiming.connectTimeoutSeconds)
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
