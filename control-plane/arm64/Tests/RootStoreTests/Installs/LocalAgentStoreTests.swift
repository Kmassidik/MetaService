import XCTest
@testable import RootStore

final class LocalAgentStoreTests: XCTestCase {
    private var store: LocalAgentStore!

    override func setUpWithError() throws {
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = LocalAgentStore(database)
    }

    func testAnAgentIsKeptWithItsArgumentsAndCanBeReplacedOrRemoved() throws {
        let entry = LocalAgentEntry(machine: "mini", binary: "/bin/agent", arguments: ["run", "--port", "9101"], logPath: "/tmp/a.log", port: 9101)
        try store.save(entry)
        XCTAssertEqual(try store.all(), [entry])
        let changed = LocalAgentEntry(machine: "mini", binary: "/bin/agent2", arguments: ["run"], logPath: "/tmp/b.log", port: 9102)
        try store.save(changed)
        XCTAssertEqual(try store.all(), [changed])
        try store.remove(machine: "mini")
        XCTAssertEqual(try store.all(), [])
    }

    func testArgumentsWithOddCharactersComeBackExactly() throws {
        let odd = LocalAgentEntry(machine: "m", binary: "/b", arguments: ["--name", "it's \"quoted\" ; $(x)", "日本"], logPath: "/l", port: 1)
        try store.save(odd)
        XCTAssertEqual(try store.all().first?.arguments, odd.arguments)
    }
}
