import XCTest
@testable import RootCore

final class OrderFollowingTests: XCTestCase {
    func testTheParentFollowsACreateLongerThanTheHelperCanTakeToMakeAVm() {
        XCTAssertGreaterThan(OrderFollowing.giveUpAfterSeconds, OrderFollowing.longestCreateSeconds, "the parent must not give up on a VM the helper is still starting")
    }

    func testTheHelperGetsTwoTriesOfAboutAMinuteEach() {
        XCTAssertEqual(OrderFollowing.helperTries, 2)
        XCTAssertGreaterThanOrEqual(OrderFollowing.helperStartSeconds, 60)
    }

    func testContactIsLostOnlyAfterAGoodWhileOfSilence() {
        XCTAssertGreaterThanOrEqual(OrderFollowing.lostContactAfterPolls * OrderFollowing.pollSeconds, 5 * 60)
    }
}
