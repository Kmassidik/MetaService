import Foundation
import RootCore
import XCTest
@testable import RootStore

final class GpuBookingStoreTests: XCTestCase {
    private var database: Database!
    private var store: GpuBookingStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let thirtyTwoGb = GpuRoom(announcesLimit: true, totalGb: 32, bookedGb: 0)

    override func setUpWithError() throws {
        database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = GpuBookingStore(database)
    }

    private func book(_ key: String, _ gb: Int, machine: String = "dgx") throws {
        try store.book(machine: machine, key: key, gb: gb, room: thirtyTwoGb, now: now)
    }

    func testBookingsAddUpPerMachine() throws {
        try book("a", 4)
        try book("b", 8)
        try book("c", 16, machine: "other")
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 12)
        XCTAssertEqual(try store.bookedGb(machine: "other"), 16)
        XCTAssertEqual(try store.bookedGb(machine: "nobody"), 0)
        XCTAssertEqual(try store.bookings(machine: "dgx"), ["a": 4, "b": 8])
    }

    func testTheLastFreeGbFitsAndTheNextOneIsRefusedWithTheNumbers() throws {
        try book("a", 31)
        XCTAssertNoThrow(try book("b", 1))
        XCTAssertThrowsError(try book("c", 1)) {
            XCTAssertEqual(($0 as? GpuBookingRefusal)?.code, "gpu_memory_not_available")
            XCTAssertEqual(($0 as? GpuBookingRefusal)?.freeGb, 0)
        }
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 32, "a refused request books nothing")
    }

    func testTheSumIsReadFromTheStoreNotFromTheRoomPassedIn() throws {
        try book("a", 30)
        let stale = GpuRoom(announcesLimit: true, totalGb: 32, bookedGb: 0)
        XCTAssertThrowsError(try store.book(machine: "dgx", key: "b", gb: 4, room: stale, now: now))
    }

    func testAHelperThatDoesNotAnnounceBooksNothing() {
        let old = GpuRoom(announcesLimit: false, totalGb: 32, bookedGb: 0)
        XCTAssertThrowsError(try store.book(machine: "dgx", key: "a", gb: 1, room: old, now: now)) { XCTAssertEqual(($0 as? GpuBookingRefusal)?.code, "helper_too_old") }
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 0)
    }

    func testReleasingFreesTheMemoryAndMovingKeepsIt() throws {
        try book("rc-1", 8)
        try store.move(machine: "dgx", from: "rc-1", to: "wl-1")
        XCTAssertEqual(try store.bookings(machine: "dgx"), ["wl-1": 8])
        try store.release(machine: "dgx", key: "wl-1")
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 0)
        XCTAssertNoThrow(try book("again", 32))
    }

    func testRemovingTheMachineFreesEverythingOnIt() throws {
        try book("a", 8)
        try book("b", 8, machine: "other")
        try store.release(machine: "dgx")
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 0)
        XCTAssertEqual(try store.bookedGb(machine: "other"), 8)
    }

    func testTwoRequestsAtOnceForTheLastFreeGbHaveExactlyOneWinner() throws {
        try book("a", 31)
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 8) { index in
            results.add(succeeded: (try? book("racer-\(index)", 1)) != nil)
        }
        XCTAssertEqual(results.wins, 1)
        XCTAssertEqual(try store.bookedGb(machine: "dgx"), 32)
    }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var wins: Int { lock.lock(); defer { lock.unlock() }; return count }
    func add(succeeded: Bool) { lock.lock(); defer { lock.unlock() }; count += succeeded ? 1 : 0 }
}
