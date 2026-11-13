import Foundation
import MSCore
import RootCore
import RootStore

/// Reads the router's WAN counters every interval, turns them into per-minute usage and writes finished minutes to the store.
/// Not configured: the loop never starts. A failed poll keeps the previous counters, so the next good one does not count the gap as one huge delta.
/// Problems change the status text and write one stderr line when the state changes, never one line per poll.
actor OfficeBandwidthSampler {
    /// Builds the SNMP client for a target. Tests pass a fake; the Root uses the UDP transport.
    typealias ClientFactory = @Sendable (OfficeSnmpTarget) throws -> SnmpClient

    /// The last good reading of one WAN index and the time it was taken (epoch seconds).
    private struct PreviousReading {
        let at: Int
        let pair: OfficeCounterPair
    }

    /// The bytes one interval moved and how many seconds it covered.
    private struct CountedInterval {
        let traffic: OfficeTraffic
        let seconds: Int
    }

    private let target: OfficeSnmpTarget?
    private let store: OfficeMinuteStore
    private let clock: Clock
    private let makeClient: ClientFactory
    private let reader = OfficeCounterReader()
    private var accumulator = OfficeMinuteAccumulator()
    private var previous: [Int: PreviousReading] = [:]
    private var names: [OfficeInterface] = []
    private var current: OfficeStatus
    private var lastPoll: Int?
    private var lastWalk: Int?
    private var lastFlush: Int?
    private var lastPrune: Int?
    private var storeFailing = false

    init(settings: OfficeSnmpSettings, store: OfficeMinuteStore, clock: Clock, makeClient: @escaping ClientFactory = OfficeBandwidthSampler.udpClient) {
        target = settings.target
        self.store = store
        self.clock = clock
        self.makeClient = makeClient
        current = settings.target == nil ? .notConfigured : .waiting
    }

    /// The SNMP client over UDP to the target's address. The address was checked as IPv4 when the settings were read.
    static func udpClient(_ target: OfficeSnmpTarget) throws -> SnmpClient {
        SnmpClient(transport: try UdpSnmpTransport(ipv4Address: target.host), community: target.community)
    }

    /// The current status of the poller.
    func status() -> OfficeStatus {
        current
    }

    /// The WAN names from the last walk of the interface table.
    func interfaces() -> [OfficeInterface] {
        names
    }

    /// A fresh walk of the interface table now. Returns nothing when the router is not configured. Updates the names kept for the usage route.
    func liveInterfaces() async throws -> [OfficeInterface] {
        guard let target else { return [] }
        names = try await Self.walkNames(try makeClient(target))
        return names
    }

    /// Polls the router every interval, and flushes and prunes when due. Returns at once when the router is not configured.
    func run() async {
        guard let target else { return }
        let tickSeconds = min(target.intervalSeconds, OfficeRules.flushSeconds)
        while !Task.isCancelled {
            if isDue(lastPoll, every: target.intervalSeconds) {
                await pollOnce()
            }
            maintain()
            // A cancelled sleep ends early; the loop condition then stops the task. That is the only way out, so nothing is lost.
            try? await Task.sleep(for: .seconds(tickSeconds))
        }
    }

    /// One poll: read the counters, count the intervals, then refresh the names when due. Any failure sets the status to a fixed text.
    func pollOnce() async {
        guard let target else { return }
        let now = epochNow()
        lastPoll = now
        do {
            let client = try makeClient(target)
            let readings = try await reader.read(target.wanIndexes, using: client)
            record(readings, at: now, intervalSeconds: target.intervalSeconds)
            try await refreshNamesIfDue(now, client: client)
            setStatus(OfficeStatus(state: .ok, detail: OfficeFailure.okPhrase, lastOkAt: now))
        } catch {
            setStatus(OfficeStatus(state: .failed, detail: OfficeFailure.phrase(for: error), lastOkAt: current.lastOkAt))
        }
    }

    /// Writes the minutes still being built when a flush is due, and deletes old minutes when a prune is due.
    func maintain() {
        let now = epochNow()
        if isDue(lastFlush, every: OfficeRules.flushSeconds) {
            lastFlush = now
            save(accumulator.takeOpenMinutes())
        }
        if isDue(lastPrune, every: OfficeRules.pruneSeconds) {
            lastPrune = now
            storeWork { try store.deleteOlderThan(minute: cutoffMinute(now)) }
        }
    }

    /// Counts each WAN's interval against its last good reading, then keeps the new reading for the next one.
    private func record(_ readings: [Int: OfficeCounterPair], at now: Int, intervalSeconds: Int) {
        for (index, pair) in readings {
            let counted = countedInterval(for: index, pair, now: now, intervalSeconds: intervalSeconds)
            previous[index] = PreviousReading(at: now, pair: pair)
            guard let counted else { continue }
            save(accumulator.add(wanIndex: index, at: now, inBytes: counted.traffic.inBytes,
                                 outBytes: counted.traffic.outBytes, seconds: counted.seconds))
        }
    }

    /// The interval since the last good reading, or nil when there is none, it is too long ago, or a counter cannot give a count.
    private func countedInterval(for index: Int, _ pair: OfficeCounterPair, now: Int, intervalSeconds: Int) -> CountedInterval? {
        guard let before = previous[index] else { return nil }
        let seconds = now - before.at
        guard seconds > 0, seconds <= OfficeRules.maxGapIntervals * intervalSeconds else { return nil }
        guard let inBytes = OfficeDelta.bytes(previous: before.pair.inCounter, now: pair.inCounter),
              let outBytes = OfficeDelta.bytes(previous: before.pair.outCounter, now: pair.outCounter) else { return nil }
        return CountedInterval(traffic: OfficeTraffic(inBytes: inBytes, outBytes: outBytes), seconds: seconds)
    }

    /// Walks the interface table when the last walk is an hour old or more. The walk time is kept even when the walk fails, so it is not retried every poll.
    private func refreshNamesIfDue(_ now: Int, client: SnmpClient) async throws {
        guard isDue(lastWalk, every: OfficeRules.walkSeconds) else { return }
        lastWalk = now
        names = try await Self.walkNames(client)
    }

    /// The names of the interfaces in the table, sorted by index. Entries that are not direct instances are skipped.
    private static func walkNames(_ client: SnmpClient) async throws -> [OfficeInterface] {
        guard let prefix = SnmpOid(arcs: OfficeRules.ifDescr) else {
            throw SnmpError.badResponse("bad ifDescr OID")
        }
        let varbinds = try await client.walk(prefix, maxEntries: OfficeRules.maxWalkEntries)
        return varbinds.compactMap { interface(from: $0, baseCount: prefix.arcs.count) }.sorted { $0.index < $1.index }
    }

    /// One interface name from a walked varbind: the index is the last arc, the value is the name text.
    private static func interface(from varbind: SnmpVarbind, baseCount: Int) -> OfficeInterface? {
        guard varbind.oid.arcs.count == baseCount + 1, let index = varbind.oid.arcs.last,
              case .octets(let bytes) = varbind.value else { return nil }
        return OfficeInterface(index: Int(index), name: String(decoding: bytes, as: UTF8.self))
    }

    /// Adds finished minutes to the store. Nothing to add is not a write.
    private func save(_ minutes: [OfficeMinute]) {
        guard !minutes.isEmpty else { return }
        storeWork { try store.record(minutes) }
    }

    /// Runs one store write and reports its state change on stderr.
    private func storeWork(_ work: () throws -> Void) {
        do {
            try work()
            reportStore(nil)
        } catch {
            reportStore(error)
        }
    }

    /// Writes one stderr line when the store starts failing, and one when it works again. Repeats of the same state are silent.
    private func reportStore(_ error: Error?) {
        guard (error != nil) != storeFailing else { return }
        storeFailing = error != nil
        guard let error else {
            writeStderr("metaservice-root: office bandwidth writes work again")
            return
        }
        writeStderr("metaservice-root: office bandwidth write failed: \(error)")
    }

    /// Stores the new status and writes one stderr line when its state or text changed. The last-good time alone does not count as a change.
    private func setStatus(_ next: OfficeStatus) {
        let changed = next.state != current.state || next.detail != current.detail
        current = next
        guard changed else { return }
        writeStderr("metaservice-root: office bandwidth: \(next.detail)")
    }

    private func writeStderr(_ line: String) {
        FileHandle.standardError.write(Data("\(line)\n".utf8))
    }

    private func isDue(_ last: Int?, every seconds: Int) -> Bool {
        guard let last else { return true }
        return epochNow() - last >= seconds
    }

    private func epochNow() -> Int {
        Int(clock.now.timeIntervalSince1970)
    }

    /// The first minute that is still kept: the minute `keepDays` days before now.
    private func cutoffMinute(_ now: Int) -> Int {
        (now - OfficeRules.keepDays * NetUsageRules.secondsPerDay) / OfficeRules.secondsPerMinute
    }
}
