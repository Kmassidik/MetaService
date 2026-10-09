import XCTest
import RootCore
@testable import RootStore

final class MachineSettingsStoreTests: XCTestCase {
    func testSettingsAreKeptReplacedAndRemoved() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        let store = MachineSettingsStore(database)
        XCTAssertNil(try store.get(machine: "mini"))
        let settings = MachineSettings(profile: "apple-silicon-mac", labels: ["office"], notes: "it's \"quoted\"", ramReserveMb: 4096, vmMaxRunning: 3, subdomain: "mini", publicChat: true, aiModel: "m/x")
        try store.save(settings, machine: "mini")
        XCTAssertEqual(try store.get(machine: "mini"), settings)
        try store.save(MachineSettings(profile: "custom"), machine: "mini")
        XCTAssertEqual(try store.get(machine: "mini")?.profile, "custom")
        try store.remove(machine: "mini")
        XCTAssertNil(try store.get(machine: "mini"))
    }
}
