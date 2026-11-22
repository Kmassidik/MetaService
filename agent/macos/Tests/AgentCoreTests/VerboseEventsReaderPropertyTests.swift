import XCTest
import AgentCore

/// Property tests for the invariants in docs/security-model.md §3, checked over randomized
/// connection sequences: cursor monotonicity (I1), no window overlap (I2), exactly-once per
/// connection (I3), dedupe soundness (I4), and restart safety (I5).
final class VerboseEventsReaderPropertyTests: XCTestCase {
    /// A deterministic PRNG so a failure reproduces.
    private func rng(seed: UInt64) -> () -> UInt64 {
        var state = seed
        return {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    /// A fake log: every window returns the sightings whose epoch falls inside it. Records the
    /// windows asked for, so the test can check I1 and I2 on the reader's behavior.
    private final class FakeLog: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var windows: [(start: Int, end: Int)] = []
        let sightings: [VerboseSighting]
        init(sightings: [VerboseSighting]) { self.sightings = sightings }

        func read(start: Int, end: Int) -> String {
            lock.lock(); defer { lock.unlock() }
            windows.append((start, end))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")!
            return sightings.filter { $0.epoch >= start && $0.epoch < end }
                .map { formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0.epoch))) + ".000 E  sshd-session[\($0.pid):a1] Invalid user \($0.user ?? "x") from \($0.address ?? "0.0.0.0") port 5" }
                .joined(separator: "\n")
        }

        func windowPairs() -> [(prev: (Int, Int)?, next: (Int, Int))] {
            var pairs: [(prev: (Int, Int)?, next: (Int, Int))] = []
            for (index, window) in windows.enumerated() {
                pairs.append((index > 0 ? windows[index - 1] : nil, window))
            }
            return pairs
        }

        func reset() { lock.lock(); windows = []; lock.unlock() }
    }

    /// Random connections: pid p connects at time t, possibly again later (same pid, new epoch).
    private func randomSightings(seed: UInt64, count: Int, baseEpoch: Int = 1_700_000_000) -> [VerboseSighting] {
        let next = rng(seed: seed)
        var sightings: [VerboseSighting] = []
        for index in 0..<count {
            let pid = 100 + index
            let first = baseEpoch + Int(next() % 3600)
            sightings.append(VerboseSighting(epoch: first, pid: pid, user: "u\(index)", address: "10.0.0.\(index)", failed: true, method: nil))
            // 30% connect a second time within the dedupe window (same connection, more lines)
            if next() % 10 < 3 {
                let again = first + Int(next() % 60)
                sightings.append(VerboseSighting(epoch: again, pid: pid, user: "u\(index)", address: "10.0.0.\(index)", failed: true, method: nil))
            }
        }
        return sightings.sorted { $0.epoch < $1.epoch }
    }

    func testWindowsAreConsecutiveAndMonotonic() async throws {
        for seed: UInt64 in [1, 2, 3] {
            let log = FakeLog(sightings: randomSightings(seed: seed, count: 40))
            let now = 1_700_000_000 + 7200
            let reader = VerboseEventsReader(zone: TimeZone(identifier: "Asia/Jakarta")!, now: { now }, uptime: { 100 }, readLog: { start, end, _ in
                log.read(start: start, end: end)
            })
            // drive the reads through the service path directly
            var after: String? = nil
            for _ in 0..<4 {
                let page = try await reader.read(after: after, limit: 2000)
                after = page.cursor
            }
            for pair in log.windowPairs() {
                if let prev = pair.prev {
                    // I2: no overlap — the next window starts at or after the previous end
                    XCTAssertGreaterThanOrEqual(pair.next.0, prev.1, "seed \(seed): window overlap")
                    // I1: monotonic — never moves backwards
                    XCTAssertGreaterThanOrEqual(pair.next.1, pair.next.0, "seed \(seed): inverted window")
                }
            }
        }
    }

    func testEachConnectionCountsExactlyOnceAcrossRestarts() async throws {
        for seed: UInt64 in [4, 5] {
            let sightings = randomSightings(seed: seed, count: 30)
            let totalAttempts = Set(sightings.map { $0.pid }).count // one event per pid
            // A restart is a fresh reader over the same 24h of log. The parent merges hourly
            // counts, so the SECOND full read must not add new connections for pids it has
            // already seen — but a fresh reader has no memory, so the reader contract is: a
            // re-read of already-read windows is only safe when the parent passes the cursor.
            // Simulate the parent's cursor discipline: first reader, then a second reader fed
            // `after` from the first page (what a restart with a stored cursor does).
            let log = FakeLog(sightings: sightings)
            let now = 1_700_000_000 + 7200
            let first = VerboseEventsReader(zone: TimeZone(identifier: "Asia/Jakarta")!, now: { now }, uptime: { 100 }, readLog: { start, end, _ in
                log.read(start: start, end: end)
            })
            log.reset()
            let page1 = try await first.read(after: nil, limit: 2000)
            let seenOnce = page1.events.filter { $0.type == .failedLogin }.count
            // every pid appears exactly once in the first pass (I3)
            XCTAssertEqual(seenOnce, totalAttempts, "seed \(seed): one event per connection")
            // second reader, cursor from the first: no windows left → no events (I5 restart safety)
            log.reset()
            let second = VerboseEventsReader(zone: TimeZone(identifier: "Asia/Jakarta")!, now: { now }, uptime: { 100 }, readLog: { start, end, _ in
                log.read(start: start, end: end)
            })
            let page2 = try await second.read(after: page1.cursor, limit: 2000)
            XCTAssertTrue(page2.events.isEmpty, "seed \(seed): re-read after the cursor added events")
        }
    }

    func testDedupeWindowExceedsLineRegapparition() async throws {
        // I4: a pid seen twice within 24h is one connection. Two sightings of one pid within the
        // window produce one event, whatever their distance.
        let base = 1_700_000_000
        for gap in [1, 60, 3600, 86_000] {
            let sightings = [
                VerboseSighting(epoch: base, pid: 7, user: "root", address: "1.1.1.1", failed: true, method: nil),
                VerboseSighting(epoch: base + gap, pid: 7, user: "root", address: "1.1.1.1", failed: true, method: nil),
            ]
            let log = FakeLog(sightings: sightings)
            let now = base + 7200
            let reader = VerboseEventsReader(zone: TimeZone(identifier: "Asia/Jakarta")!, now: { now }, uptime: { 100 }, readLog: { start, end, _ in
                log.read(start: start, end: end)
            })
            let page = try await reader.read(after: nil, limit: 2000)
            XCTAssertEqual(page.events.filter { $0.type == .failedLogin }.count, 1, "gap \(gap)s: one connection")
        }
    }
}

