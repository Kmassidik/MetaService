import XCTest
import RootCore
@testable import RootStore

final class BundleCommandStoreTests: XCTestCase {
    private var database: Database!
    private var commands: CommandStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        try MachineStore(database).enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        commands = CommandStore(database)
    }

    private func make(_ id: String, _ type: String, workload: String? = nil, at offset: TimeInterval) throws {
        try commands.create(id: id, machine: "mini", workloadId: workload, type: type, params: [:], actor: "k", now: now.addingTimeInterval(offset))
    }

    func testTheNewestChatCommandIsTheOneThatCounts() throws {
        try make("a", "bundle_install", at: 0)
        try make("b", "bundle_uninstall", at: 10)
        XCTAssertEqual(try commands.lastBundleCommand(machine: "mini", workloadId: nil)?.id, "b")
        try make("c", "bundle_install", at: 20)
        XCTAssertEqual(try commands.lastBundleCommand(machine: "mini", workloadId: nil)?.id, "c")
    }

    func testCommandsOfOtherKindsAndOtherTargetsAreNotChatCommands() throws {
        try make("stop", "stop", workload: "w-1", at: 5)
        try make("inside", "bundle_install", workload: "w-1", at: 6)
        XCTAssertNil(try commands.lastBundleCommand(machine: "mini", workloadId: nil))
        XCTAssertEqual(try commands.lastBundleCommand(machine: "mini", workloadId: "w-1")?.id, "inside")
        XCTAssertNil(try commands.lastBundleCommand(machine: "nobody", workloadId: nil))
    }

    func testOnlyAnUnfinishedChatCommandIsGoing() throws {
        XCTAssertNil(try commands.goingBundleCommand(machine: "mini", workloadId: nil))
        try make("a", "bundle_uninstall", at: 0)
        XCTAssertEqual(try commands.goingBundleCommand(machine: "mini", workloadId: nil), .uninstall)
        try commands.update(id: "a", state: "running", result: nil, now: now)
        XCTAssertEqual(try commands.goingBundleCommand(machine: "mini", workloadId: nil), .uninstall)
        try commands.update(id: "a", state: "succeeded", result: nil, now: now)
        XCTAssertNil(try commands.goingBundleCommand(machine: "mini", workloadId: nil))
        try make("b", "bundle_install", at: 10)
        XCTAssertEqual(try commands.goingBundleCommand(machine: "mini", workloadId: nil), .install)
    }
}
