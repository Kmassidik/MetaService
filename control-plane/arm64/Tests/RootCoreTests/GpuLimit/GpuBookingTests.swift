import XCTest
@testable import RootCore

final class GpuBookingTests: XCTestCase {
    private func card(_ memoryMb: Int?, vendor: String = "nvidia") -> GpuInfo {
        GpuInfo(vendor: vendor, model: "RTX", memoryMb: memoryMb)
    }

    private func room(total: Int?, booked: Int, announces: Bool = true) -> GpuRoom {
        GpuRoom(announcesLimit: announces, totalGb: total, bookedGb: booked)
    }

    func testTheTotalIsTheFirstCardsMemoryInWholeGbRoundedDown() {
        XCTAssertEqual(GpuBooking.totalGb(gpu: [card(32607)]), 31)
        XCTAssertEqual(GpuBooking.totalGb(gpu: [card(32768)]), 32)
        XCTAssertEqual(GpuBooking.totalGb(gpu: [card(1023)]), 0)
    }

    func testTheTotalIsUnknownWithoutACardOrItsMemory() {
        XCTAssertNil(GpuBooking.totalGb(gpu: []))
        XCTAssertNil(GpuBooking.totalGb(gpu: [card(nil)]))
        XCTAssertNil(GpuBooking.totalGb(gpu: [card(0)]))
    }

    func testAMachineWithTwoCardsUsesTheFirstOnly() {
        XCTAssertEqual(GpuBooking.totalGb(gpu: [card(24576), card(81920)]), 24)
    }

    func testALimitThatFillsTheCardExactlyFits() {
        XCTAssertNil(GpuBooking.refusal(room(total: 32, booked: 0), requestedGb: 32))
        XCTAssertNil(GpuBooking.refusal(room(total: 32, booked: 28), requestedGb: 4))
    }

    func testOneGbOverIsRefusedWithTheNumbers() throws {
        let refusal = try XCTUnwrap(GpuBooking.refusal(room(total: 32, booked: 28), requestedGb: 5))
        XCTAssertEqual(refusal.code, "gpu_memory_not_available")
        XCTAssertEqual(refusal.freeGb, 4)
        XCTAssertEqual(refusal.message, "Only 4 GB of the card's 32 GB is still free to book.")
    }

    func testAFullCardRefusesEvenOneGbAndSaysZeroIsFree() throws {
        let refusal = try XCTUnwrap(GpuBooking.refusal(room(total: 8, booked: 8), requestedGb: 1))
        XCTAssertEqual(refusal.freeGb, 0)
        XCTAssertEqual(refusal.message, "Only 0 GB of the card's 8 GB is still free to book.")
    }

    func testAnOverBookedCardNeverShowsNegativeFreeMemory() throws {
        XCTAssertEqual(try XCTUnwrap(GpuBooking.refusal(room(total: 8, booked: 12), requestedGb: 1)).freeGb, 0)
        XCTAssertEqual(GpuBooking.summary(total: 8, booked: 12), GpuBookingSummary(totalGb: 8, bookedGb: 12, freeGb: 0))
    }

    func testUnknownCardMemoryRefusesAnyLimit() throws {
        let refusal = try XCTUnwrap(GpuBooking.refusal(room(total: nil, booked: 0), requestedGb: 1))
        XCTAssertEqual(refusal.code, "gpu_memory_unknown")
        XCTAssertNil(refusal.freeGb)
    }

    func testAHelperThatDoesNotAnnounceTheLimitIsTooOldAndIsAskedFirst() throws {
        let refusal = try XCTUnwrap(GpuBooking.refusal(room(total: nil, booked: 0, announces: false), requestedGb: 1))
        XCTAssertEqual(refusal.code, "helper_too_old")
        XCTAssertEqual(refusal.message, "Update the helper on this machine first.")
    }

    func testTheSummaryHasNothingWhenTheTotalIsUnknown() {
        XCTAssertNil(GpuBooking.summary(total: nil, booked: 0))
        XCTAssertEqual(GpuBooking.summary(total: 32, booked: 12), GpuBookingSummary(totalGb: 32, bookedGb: 12, freeGb: 20))
    }
}
