import XCTest
@testable import RootCore

final class StatsQueryTests: XCTestCase {
    func testNoParameterMeansTheProcessListIsIncluded() throws {
        XCTAssertTrue(try StatsQuery.wantsProcesses(values: []))
    }

    func testOneAndZero() throws {
        XCTAssertTrue(try StatsQuery.wantsProcesses(values: ["1"]))
        XCTAssertFalse(try StatsQuery.wantsProcesses(values: ["0"]))
    }

    func testAnythingElseIsRefused() {
        for bad in ["", "2", "true", "false", "yes", " 1", "1 ", "-1", "01", "1;rm", "../x", "0&x=1"] {
            XCTAssertThrowsError(try StatsQuery.wantsProcesses(values: [bad]), "'\(bad)' must be refused")
        }
    }

    func testTheParameterGivenTwiceIsRefused() {
        XCTAssertThrowsError(try StatsQuery.wantsProcesses(values: ["1", "0"]))
        XCTAssertThrowsError(try StatsQuery.wantsProcesses(values: ["0", "0"]))
    }

    func testTheHelperIsOnlyEverAskedWithFixedPaths() {
        XCTAssertEqual(StatsQuery.helperPath(processes: true), "/v1/stats")
        XCTAssertEqual(StatsQuery.helperPath(processes: false), "/v1/stats?processes=0")
    }

    func testWithoutProcessesDropsTheListAndKeepsTheRest() throws {
        let json = #"{"taken_at":"2026-10-21T10:00:00Z","measuring":false,"uptime_seconds":5,"cpu":{"core_count":1,"total_percent":1.0,"cores_percent":[1.0],"load":{"one":1,"five":1,"fifteen":1}},"memory":{"total_bytes":10,"used_bytes":1,"cached_bytes":1,"free_bytes":8,"swap_total_bytes":0,"swap_used_bytes":0},"disks":[],"network":{"received_total_bytes":1,"sent_total_bytes":1,"received_bytes_per_second":1.0,"sent_bytes_per_second":1.0},"processes":[{"pid":1,"name":"a","user":"b","cpu_percent":1.0,"memory_bytes":1}]}"#
        let stats = try MachineStats.parse(Data(json.utf8))
        XCTAssertEqual(stats.processes.count, 1)
        let plain = stats.withoutProcesses()
        XCTAssertEqual(plain.processes, [])
        XCTAssertEqual(plain.uptimeSeconds, stats.uptimeSeconds)
        XCTAssertEqual(plain.memory, stats.memory)
    }
}
