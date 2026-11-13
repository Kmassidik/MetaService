import XCTest
import AgentCore
@testable import Agent

/// Timing probe, runs only when BENCH_ROOT is set. Not a pass/fail test.
final class DarwinStorageBenchTests: XCTestCase {
    func testWalkTiming() throws {
        guard let root = ProcessInfo.processInfo.environment["BENCH_ROOT"] else { throw XCTSkip("BENCH_ROOT not set") }
        let started = Date()
        let walked = try DarwinStorageWalker(root: root, allowedDevices: [], skip: [], counters: StorageCounters()).walk(floor: 1_048_576)
        print("BENCH entries=\(walked.entries) bytes=\(walked.root.bytes) seconds=\(Date().timeIntervalSince(started))")
    }
}
