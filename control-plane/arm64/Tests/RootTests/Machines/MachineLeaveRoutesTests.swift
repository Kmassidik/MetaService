import XCTest
import RootCore
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
        XCTAssertTrue(old?.message.contains("too old") ?? false)
        XCTAssertEqual(failure(MachineLeaveRoutes.outcome(status: 404, errorCode: nil, message: nil))?.code, "old_helper")
    }

    func testNoAnswerAtAllIsUnreachable() {
        XCTAssertEqual(failure(MachineLeaveRoutes.outcome(status: 0, errorCode: nil, message: nil))?.code, "unreachable")
    }
}

final class HelperSelfUpdateOutcomeTests: XCTestCase {
    private func failure(_ result: Result<HelperUpdateResult, ApiFailure>) -> ApiFailure? {
        if case .failure(let failure) = result { return failure }
        return nil
    }

    func testAnAcceptedUpdateIsStartedNotDone() {
        guard case .success(let answer) = HelperUpdateService.pushOutcome(status: 200, errorCode: nil, message: nil) else { return XCTFail("expected success") }
        XCTAssertEqual(answer.result, "started")
        XCTAssertTrue(answer.message.contains("put back"))
    }

    func testAnOldHelperIsToldWhatToDoOnce() {
        let old = failure(HelperUpdateService.pushOutcome(status: 404, errorCode: "not_found", message: nil))
        XCTAssertEqual(old?.code, "old_helper")
        XCTAssertTrue(old?.message.contains("join again once") ?? false)
    }

    func testAFailedDownloadSaysWhy() {
        let refused = failure(HelperUpdateService.pushOutcome(status: 409, errorCode: "update_failed", message: "the downloaded helper is not the build the panel asked for"))
        XCTAssertEqual(refused?.code, "update_failed")
        XCTAssertTrue(refused?.message.contains("not the build") ?? false)
    }

    func testNoAnswerIsUnreachable() {
        XCTAssertEqual(failure(HelperUpdateService.pushOutcome(status: 0, errorCode: nil, message: nil))?.code, "unreachable")
    }
}
