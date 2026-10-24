import Foundation
import RootCore
import XCTest
@testable import RootStore

final class SandboxStoreTests: XCTestCase {
    private var database: Database!
    private var store: SandboxStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let shape = SandboxShape(vcpu: 2, ramMb: 512, diskMb: 1_024)

    private var roomy: TeamLimits {
        TeamLimits(maxRunning: 10, maxVcpu: 100, maxRamMb: 100_000, maxSandboxesPerHour: 100)
    }

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = SandboxStore(database)
        try TeamStore(database).create(id: "team-1", name: "Team", now: now)
    }

    @discardableResult
    private func create(_ id: String, at when: Date? = nil, limits: TeamLimits? = nil) throws -> SandboxRecord {
        let moment = when ?? now
        let new = NewSandbox(id: id, team: "team-1", machine: "m1", template: "base", shape: shape,
                             endAt: moment.addingTimeInterval(300), state: .running)
        return try store.create(new, limits: limits ?? roomy, now: moment)
    }

    func testASandboxRoundTripsWithItsShapeAndEndTime() throws {
        let made = try create("sbx-1")
        XCTAssertEqual(try store.get(id: "sbx-1"), made)
        XCTAssertEqual(made.state, .running)
        XCTAssertEqual(made.shape, shape)
        XCTAssertEqual(made.endAt, now.addingTimeInterval(300))
        XCTAssertNil(made.endedAt)
        XCTAssertNil(made.endedReason)
        XCTAssertEqual(made.remainingSeconds(now: now), 300)
        XCTAssertNil(try store.get(id: "nobody"))
    }

    func testTheListIsNewestFirst() throws {
        try create("old", at: now)
        try create("new", at: now.addingTimeInterval(10))
        XCTAssertEqual(try store.list(team: "team-1").map(\.id), ["new", "old"])
        XCTAssertEqual(try store.list(team: "nobody"), [])
    }

    func testADuplicateIdIsRefused() throws {
        try create("sbx-1")
        XCTAssertThrowsError(try create("sbx-1"))
        XCTAssertEqual(try store.list(team: "team-1").count, 1)
    }

    func testTheRunningLimitRefusesTheNextCreate() throws {
        let tight = TeamLimits(maxRunning: 1, maxVcpu: 100, maxRamMb: 100_000, maxSandboxesPerHour: 100)
        try create("one", limits: tight)
        XCTAssertThrowsError(try create("two", limits: tight)) {
            XCTAssertEqual(($0 as? TeamLimitRefusal)?.reason, .tooManyRunning)
        }
        XCTAssertEqual(try store.list(team: "team-1").map(\.id), ["one"], "a refused create writes nothing")
    }

    func testTheVcpuLimitRefusesAShapeThatWouldNotFit() throws {
        let tight = TeamLimits(maxRunning: 10, maxVcpu: 3, maxRamMb: 100_000, maxSandboxesPerHour: 100)
        try create("one", limits: tight)
        XCTAssertThrowsError(try create("two", limits: tight)) {
            XCTAssertEqual(($0 as? TeamLimitRefusal)?.reason, .tooMuchVcpu)
        }
    }

    func testTheMemoryLimitRefusesAShapeThatWouldNotFit() throws {
        let tight = TeamLimits(maxRunning: 10, maxVcpu: 100, maxRamMb: 512, maxSandboxesPerHour: 100)
        try create("one", limits: tight)
        XCTAssertThrowsError(try create("two", limits: tight)) {
            XCTAssertEqual(($0 as? TeamLimitRefusal)?.reason, .tooMuchRam)
        }
    }

    func testTheHourlyLimitCountsEndedSandboxesInItsWindow() throws {
        let tight = TeamLimits(maxRunning: 10, maxVcpu: 100, maxRamMb: 100_000, maxSandboxesPerHour: 1)
        try create("one", limits: tight)
        _ = try store.end(id: "one", at: now.addingTimeInterval(60), reason: .deleted)
        XCTAssertThrowsError(try create("two", at: now.addingTimeInterval(120), limits: tight)) {
            XCTAssertEqual(($0 as? TeamLimitRefusal)?.reason, .tooManyPerHour)
        }
        XCTAssertNoThrow(try create("three", at: now.addingTimeInterval(Double(TeamLimits.hourlyWindowSeconds) + 1), limits: tight),
                         "the window has moved past the first create")
    }

    func testAPausedSandboxFreesItsSlotAndItsMemory() throws {
        let tight = TeamLimits(maxRunning: 1, maxVcpu: 2, maxRamMb: 512, maxSandboxesPerHour: 100)
        try create("one", limits: tight)
        XCTAssertTrue(try store.setState(id: "one", state: .paused))
        XCTAssertNoThrow(try create("two", limits: tight))
        let usage = try store.teamUsage(team: "team-1", now: now)
        XCTAssertEqual(usage.running, 1)
        XCTAssertEqual(usage.vcpu, 2)
        XCTAssertEqual(usage.ramMb, 512)
        XCTAssertEqual(usage.createdLastHour, 2)
    }

    func testTheTeamUsageAddsUpOnlyRunningSandboxes() throws {
        try create("one")
        try create("two")
        try store.setState(id: "two", state: .paused)
        let usage = try store.teamUsage(team: "team-1", now: now)
        XCTAssertEqual(usage.running, 1)
        XCTAssertEqual(usage.vcpu, 2)
        XCTAssertEqual(usage.ramMb, 512)
        XCTAssertEqual(usage.createdLastHour, 2)
        XCTAssertEqual(try store.teamUsage(team: "nobody", now: now), TeamUsage(running: 0, vcpu: 0, ramMb: 0, createdLastHour: 0))
    }

    func testEndingIsIdempotentAndKeepsTheFirstReason() throws {
        try create("one")
        let first = try XCTUnwrap(try store.end(id: "one", at: now.addingTimeInterval(60), reason: .timeout))
        XCTAssertEqual(first.state, .ended)
        XCTAssertEqual(first.endedAt, now.addingTimeInterval(60))
        XCTAssertEqual(first.endedReason, .timeout)
        let second = try XCTUnwrap(try store.end(id: "one", at: now.addingTimeInterval(90), reason: .deleted))
        XCTAssertEqual(second.endedAt, now.addingTimeInterval(60))
        XCTAssertEqual(second.endedReason, .timeout)
        XCTAssertNil(try store.end(id: "nobody", at: now, reason: .deleted))
    }

    func testTheEndTimeMovesOnlyForALivingSandbox() throws {
        try create("one")
        XCTAssertTrue(try store.moveEnd(id: "one", to: now.addingTimeInterval(600)))
        XCTAssertEqual(try store.get(id: "one")?.endAt, now.addingTimeInterval(600))
        try store.end(id: "one", at: now.addingTimeInterval(60), reason: .deleted)
        XCTAssertFalse(try store.moveEnd(id: "one", to: now.addingTimeInterval(900)))
        XCTAssertFalse(try store.setState(id: "one", state: .running))
    }

    func testAnUnknownStateIsAnErrorNotAWonder() throws {
        try database.execute("""
            INSERT INTO sandboxes (id, team, machine, state, template, vcpu, ram_mb, disk_mb, created_at, end_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text("odd"), .text("team-1"), .text("m1"), .text("sleeping"), .text("base"), .int(2), .int(512), .int(1_024),
                  .int(Int(now.timeIntervalSince1970)), .int(Int(now.addingTimeInterval(300).timeIntervalSince1970))])
        XCTAssertThrowsError(try store.get(id: "odd")) {
            XCTAssertEqual($0 as? SandboxStoreError, .unknownState("sleeping"))
        }
    }
}
