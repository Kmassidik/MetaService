import XCTest
import RootCore
@testable import RootStore

final class MachineRenameStoreTests: XCTestCase {
    private var database: Database!
    private var machines: MachineStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        machines = MachineStore(database)
        try machines.enroll(name: "mini", tokenHash: "h", commandTokenSealed: "sealed", ip: nil, now: now)
        try machines.enroll(name: "dgx", tokenHash: "h2", commandTokenSealed: "sealed", ip: nil, now: now)
    }

    func testRenamingToATrickyLegalNameKeepsTheId() throws {
        try machines.rename(id: "mini", to: "Luca's PC (RTX)")
        let seen = try machines.get(id: "mini", now: now)
        XCTAssertEqual([seen.id, seen.name], ["mini", "Luca's PC (RTX)"])
    }

    func testTwoNamesThatDifferOnlyInCapitalsAreTheSameName() throws {
        try machines.rename(id: "dgx", to: "Mac Studio")
        XCTAssertThrowsError(try machines.rename(id: "mini", to: "mac STUDIO")) { XCTAssertEqual($0 as? MachineError, .exists) }
        XCTAssertEqual(try machines.get(id: "mini", now: now).name, "mini")
    }

    func testAMachineMayChangeTheCapitalsOfItsOwnName() throws {
        try machines.rename(id: "dgx", to: "Mac Studio")
        XCTAssertNoThrow(try machines.rename(id: "dgx", to: "MAC studio"))
        XCTAssertEqual(try machines.get(id: "dgx", now: now).name, "MAC studio")
    }

    func testANewMachineCannotTakeAnotherMachinesDisplayNameInOtherCapitals() throws {
        try machines.rename(id: "mini", to: "Studio")
        let enrollments = EnrollmentStore(database)
        XCTAssertThrowsError(try enrollments.create(machineName: "studio", now: now)) { XCTAssertEqual($0 as? EnrollmentError, .machineExists) }
        XCTAssertThrowsError(try enrollments.create(machineName: "dgx", now: now), "the id of an existing machine is taken too") { XCTAssertEqual($0 as? EnrollmentError, .machineExists) }
    }
}
