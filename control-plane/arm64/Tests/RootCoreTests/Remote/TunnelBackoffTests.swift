import XCTest
@testable import RootCore

final class TunnelBackoffTests: XCTestCase {
    func testTheWaitGrowsWithEveryFailureAndStopsAtAMinute() {
        XCTAssertEqual((1...8).map { TunnelBackoff.delay(afterFailures: $0) }, [1, 2, 5, 10, 30, 60, 60, 60])
    }

    func testNoFailureYetStillWaitsTheFirstDelay() {
        XCTAssertEqual(TunnelBackoff.delay(afterFailures: 0), 1)
        XCTAssertEqual(TunnelBackoff.delay(afterFailures: -3), 1)
    }

    func testTheWaitNeverShrinks() {
        let waits = (1...20).map { TunnelBackoff.delay(afterFailures: $0) }
        XCTAssertEqual(waits, waits.sorted())
        XCTAssertLessThanOrEqual(waits.max() ?? 0, 60)
    }
}
