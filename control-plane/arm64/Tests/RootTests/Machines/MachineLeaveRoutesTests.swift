import XCTest
@testable import Root

final class MachineLeaveRoutesTests: XCTestCase {
    private func failure(_ result: Result<Void, ApiFailure>) -> ApiFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    func testAnAnswerOfOkIsASuccess() {
        XCTAssertNil(failure(MachineLeaveRoutes.outcome(status: 200, errorCode: nil, message: nil)))
    }

    func testAWrongPasswordSaysWhyAndChangesNothing() {
        let refused = failure(MachineLeaveRoutes.outcome(status: 409, errorCode: "leave_failed", message: "sudo did not accept the password"))
        XCTAssertEqual(refused?.code, "leave_failed")
        XCTAssertEqual(refused?.message, "sudo did not accept the password")
    }

    func testAComputerThatDidNotJoinThroughShareAPCHasNothingToClean() {
        XCTAssertEqual(failure(MachineLeaveRoutes.outcome(status: 404, errorCode: "not_joined", message: nil))?.code, "not_joined")
    }

    func testAnOldHelperIsToldToUpdateFirst() {
        let old = failure(MachineLeaveRoutes.outcome(status: 404, errorCode: "not_found", message: nil))
        XCTAssertEqual(old?.code, "old_helper")
        XCTAssertTrue(old?.message.contains("Update helper") ?? false)
        XCTAssertEqual(failure(MachineLeaveRoutes.outcome(status: 404, errorCode: nil, message: nil))?.code, "old_helper")
    }

    func testNoAnswerAtAllIsUnreachable() {
        XCTAssertEqual(failure(MachineLeaveRoutes.outcome(status: 0, errorCode: nil, message: nil))?.code, "unreachable")
    }
}
