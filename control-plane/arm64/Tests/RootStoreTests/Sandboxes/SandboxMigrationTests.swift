import Foundation
import RootCore
import XCTest
@testable import RootStore

final class SandboxMigrationTests: XCTestCase {
    private let tables = ["teams", "api_keys", "sandboxes", "sandbox_usage"]

    func testMigration26AddsTheSandboxTables() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        XCTAssertEqual(Migrations.latest, 26)
        let names = Set(try database.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.string("name") })
        for table in tables {
            XCTAssertTrue(names.contains(table), "migration 26 creates \(table)")
        }
    }

    func testMigratingAgainChangesNothing() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try Migrations.migrate(database)
        XCTAssertEqual(try database.query("SELECT MAX(version) AS version FROM schema_version").first?.int("version"), 26)
        XCTAssertEqual(try database.query("SELECT COUNT(*) AS steps FROM schema_version").first?.int("steps"), 26)
    }

    func testAKeyCannotBeStoredTwiceByPrefix() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try TeamStore(database).create(id: "team", name: "Team", now: Date())
        try ApiKeyStore(database).create(id: "one", team: "team", prefix: "msb_ab12cd34", secretHash: "h", now: Date())
        XCTAssertThrowsError(try ApiKeyStore(database).create(id: "two", team: "team", prefix: "msb_ab12cd34", secretHash: "h", now: Date()))
    }

    func testASandboxCannotUseATeamThatDoesNotExist() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        let new = NewSandbox(id: "s", team: "nobody", machine: "m", template: "base", shape: SandboxShape(), endAt: Date(), state: .running)
        XCTAssertThrowsError(try SandboxStore(database).create(new, limits: .standard, now: Date()))
    }
}
