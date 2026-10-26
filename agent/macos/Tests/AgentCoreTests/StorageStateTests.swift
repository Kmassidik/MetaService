import XCTest
@testable import AgentCore

final class StorageStateTests: XCTestCase {
    private final class Starts: @unchecked Sendable {
        var completions: [StorageState.Completion] = []
        var count: Int { completions.count }
    }

    private final class Clock: @unchecked Sendable {
        var value: TimeInterval = 100
    }

    private func map(_ marker: UInt64 = 1) -> StorageMap {
        let disk = StorageDisk(totalBytes: 100, usedBytes: 60, freeBytes: 40)
        let node = StorageNode(parent: -1, name: "/", type: .dir, bytes: marker, files: 0, items: 0, kind: .other, reclaim: nil, modified: nil)
        return StorageMap(root: "/", finishedAt: "2026-10-26T00:00:00Z", seconds: 0.1, entries: 1, unreadable: 0, disk: disk, nodes: [node])
    }

    func testConcurrentPostsCoalesceAndCooldownDoesNotRestart() {
        let starts = Starts()
        let clock = Clock()
        let counters = StorageCounters()
        counters.addEntry(bytes: 4096)
        let state = StorageState(counters: counters, now: { clock.value }) { starts.completions.append($0) }

        XCTAssertEqual(state.answer(), StorageAnswer(scanning: false, progress: nil, error: nil, map: nil))
        let first = state.scan()
        XCTAssertTrue(first.scanning)
        XCTAssertEqual(first.progress, StorageProgress(entries: 0, bytes: 0), "starting resets stale progress")
        counters.addEntry(bytes: 2048)
        XCTAssertTrue(state.scan().scanning)
        XCTAssertEqual(state.answer().progress, StorageProgress(entries: 1, bytes: 2048))
        XCTAssertEqual(starts.count, 1)

        starts.completions[0](.success(map()))
        XCTAssertFalse(state.scan().scanning)
        XCTAssertEqual(starts.count, 1, "an immediate rescan is refused")
        clock.value += 29
        XCTAssertFalse(state.scan().scanning)
        XCTAssertEqual(starts.count, 1)
        clock.value += 1
        XCTAssertTrue(state.scan().scanning)
        XCTAssertEqual(starts.count, 2)
    }

    func testFailureRetainsLastMapAndLaterSuccessClearsError() {
        let starts = Starts()
        let clock = Clock()
        let state = StorageState(now: { clock.value }) { starts.completions.append($0) }
        _ = state.scan()
        starts.completions[0](.success(map(10)))

        clock.value += 30
        _ = state.scan()
        XCTAssertEqual(state.answer().map?.nodes[0].bytes, 10, "the old map stays visible during a scan")
        starts.completions[1](.failure(StorageScanFailure(String(repeating: "x", count: 400))))
        XCTAssertEqual(state.answer().error?.count, 300)
        XCTAssertEqual(state.answer().map?.nodes[0].bytes, 10, "a failed scan retains the last good map")
        XCTAssertNil(state.answer().progress)

        clock.value += 30
        _ = state.scan()
        starts.completions[2](.success(map(20)))
        XCTAssertNil(state.answer().error)
        XCTAssertEqual(state.answer().map?.nodes[0].bytes, 20)
    }
}
