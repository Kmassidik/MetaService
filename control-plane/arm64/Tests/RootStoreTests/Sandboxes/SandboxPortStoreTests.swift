import Foundation
import RootCore
import XCTest
@testable import RootStore

/// The public ports of the sandboxes: one row per exposed port, idempotent by (sandbox, port), and gone with its sandbox.
final class SandboxPortStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_800_000)
    private let sandbox = "abcdefghij0123456789"

    private func database() throws -> Database {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try TeamStore(database).create(id: "team", name: "Team", now: now)
        return database
    }

    private func sandbox(_ database: Database, id: String = "abcdefghij0123456789") throws {
        let new = NewSandbox(id: id, team: "team", machine: "machine", template: "base", shape: SandboxShape(), endAt: now.addingTimeInterval(600), state: .running)
        try SandboxStore(database).create(new, limits: .standard, now: now)
    }

    func testAnExposedPortIsFoundByItsLabel() throws {
        let database = try database()
        try sandbox(database)
        let store = SandboxPortStore(database)
        let made = try store.expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now)
        XCTAssertTrue(made.created)
        XCTAssertEqual(made.record, SandboxPortRecord(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", createdAt: now))
        XCTAssertEqual(try store.find(label: "6dq5fq5uuwlio6dj"), made.record)
        XCTAssertEqual(try store.find(sandbox: sandbox, port: 8080), made.record)
        XCTAssertNil(try store.find(label: "aerukz4jvpg66ajd"))
    }

    func testExposingTheSamePortTwiceAnswersTheSameRowAndLabel() throws {
        let database = try database()
        try sandbox(database)
        let store = SandboxPortStore(database)
        let first = try store.expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now)
        let again = try store.expose(sandbox: sandbox, port: 8080, label: "aerukz4jvpg66ajd", now: now.addingTimeInterval(60))
        XCTAssertFalse(again.created)
        XCTAssertEqual(again.record, first.record)
        XCTAssertEqual(again.record.label, "6dq5fq5uuwlio6dj")
        XCTAssertEqual(try store.list(sandbox: sandbox).count, 1)
    }

    func testTwoPortsOfOneSandboxKeepTheirOwnLabels() throws {
        let database = try database()
        try sandbox(database)
        let store = SandboxPortStore(database)
        try store.expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now)
        try store.expose(sandbox: sandbox, port: 8081, label: "aerukz4jvpg66ajd", now: now)
        XCTAssertEqual(try store.list(sandbox: sandbox).map(\.port), [8080, 8081])
    }

    func testALabelCannotStandForTwoPorts() throws {
        let database = try database()
        try sandbox(database)
        let store = SandboxPortStore(database)
        try store.expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now)
        XCTAssertThrowsError(try store.expose(sandbox: sandbox, port: 8081, label: "6dq5fq5uuwlio6dj", now: now)) { error in
            XCTAssertEqual(error as? SandboxPortStoreError, .labelTaken)
        }
    }

    func testAPortCannotBeExposedOnASandboxThatIsNotThere() throws {
        let database = try database()
        XCTAssertThrowsError(try SandboxPortStore(database).expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now))
    }

    func testARemovedSandboxTakesItsPortsWithIt() throws {
        let database = try database()
        try sandbox(database)
        let store = SandboxPortStore(database)
        try store.expose(sandbox: sandbox, port: 8080, label: "6dq5fq5uuwlio6dj", now: now)
        try database.execute("DELETE FROM sandboxes WHERE id = ?", [.text(sandbox)])
        XCTAssertNil(try store.find(label: "6dq5fq5uuwlio6dj"))
        XCTAssertTrue(try store.list(sandbox: sandbox).isEmpty)
    }
}
