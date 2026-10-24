import Foundation
import RootCore
import XCTest
@testable import RootStore

final class SandboxUsageStoreTests: XCTestCase {
    private var database: Database!
    private var store: SandboxUsageStore!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let shape = SandboxShape(vcpu: 2, ramMb: 512, diskMb: 10_240)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = SandboxUsageStore(database)
    }

    func testARunIsWrittenWithItsSecondsAndWhatItHeld() throws {
        let row = try store.record(team: "team-1", sandbox: "sbx-1", startedAt: start, endedAt: start.addingTimeInterval(90), shape: shape)
        XCTAssertEqual(row.totals, SandboxUsageTotals(seconds: 90, vcpuSeconds: 180, ramMbSeconds: 46_080))
        XCTAssertEqual(try store.list(team: "team-1"), [row])
    }

    func testTheTotalsAddUpAndRespectTheWindow() throws {
        try store.record(team: "team-1", sandbox: "one", startedAt: start, endedAt: start.addingTimeInterval(90), shape: shape)
        try store.record(team: "team-1", sandbox: "two", startedAt: start.addingTimeInterval(100), endedAt: start.addingTimeInterval(130), shape: shape)
        let all = try store.totals(team: "team-1")
        XCTAssertEqual(all, SandboxUsageTotals(seconds: 120, vcpuSeconds: 240, ramMbSeconds: 61_440))
        let later = try store.totals(team: "team-1", from: start.addingTimeInterval(95), to: start.addingTimeInterval(200))
        XCTAssertEqual(later, SandboxUsageTotals(seconds: 30, vcpuSeconds: 60, ramMbSeconds: 15_360))
        XCTAssertEqual(try store.totals(team: "nobody"), SandboxUsageTotals(seconds: 0, vcpuSeconds: 0, ramMbSeconds: 0))
    }

    func testTheListIsNewestFirst() throws {
        let older = try store.record(team: "team-1", sandbox: "older", startedAt: start, endedAt: start.addingTimeInterval(10), shape: shape)
        let newer = try store.record(team: "team-1", sandbox: "newer", startedAt: start, endedAt: start.addingTimeInterval(20), shape: shape)
        try store.record(team: "team-2", sandbox: "other", startedAt: start, endedAt: start.addingTimeInterval(30), shape: shape)
        XCTAssertEqual(try store.list(team: "team-1").map(\.sandbox), [newer.sandbox, older.sandbox])
    }

    func testARunThatWentBackwardsCountsZero() throws {
        let row = try store.record(team: "team-1", sandbox: "odd", startedAt: start, endedAt: start.addingTimeInterval(-5), shape: shape)
        XCTAssertEqual(row.totals.seconds, 0)
        XCTAssertEqual(row.totals.vcpuSeconds, 0)
        XCTAssertEqual(row.totals.ramMbSeconds, 0)
    }

    func testTheListIsCappedAtItsOwnMaximum() throws {
        try store.record(team: "team-1", sandbox: "one", startedAt: start, endedAt: start.addingTimeInterval(10), shape: shape)
        XCTAssertEqual(try store.list(team: "team-1", limit: 0).count, 1)
        XCTAssertEqual(try store.list(team: "team-1", limit: SandboxUsageStore.maxList + 100).count, 1)
    }
}
