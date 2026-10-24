import Foundation
import XCTest
@testable import RootCore

final class SandboxApiRequestsTests: XCTestCase {
    // MARK: list

    func testNoQueryListsBothStatesWithTheDefaultLimit() throws {
        let query = try SandboxApiListQuery.parse([:])
        XCTAssertNil(query.states)
        XCTAssertEqual(query.limit, SandboxApiListQuery.defaultLimit)
    }

    func testOnlyRunningOrOnlyPaused() throws {
        let running = try SandboxApiListQuery.parse(["state": "running"])
        XCTAssertEqual(running.states?.contains(.running), true)
        XCTAssertEqual(running.states?.contains(.paused), false)
        XCTAssertEqual(running.states?.contains(.starting), true)
        let paused = try SandboxApiListQuery.parse(["state": "paused"])
        XCTAssertEqual(paused.states, [.paused])
        let both = try SandboxApiListQuery.parse(["state": "running,paused"])
        XCTAssertEqual(both.states?.contains(.paused), true)
    }

    func testABadStateOrLimitIs400() {
        XCTAssertThrowsError(try SandboxApiListQuery.parse(["state": "ended"]))
        XCTAssertThrowsError(try SandboxApiListQuery.parse(["limit": "0"]))
        XCTAssertThrowsError(try SandboxApiListQuery.parse(["limit": "101"]))
        XCTAssertThrowsError(try SandboxApiListQuery.parse(["limit": "ten"]))
        XCTAssertThrowsError(try SandboxApiListQuery.parse(["who": "x"]))
    }

    /// A filter we cannot honour is refused, because answering with everything would hand back sandboxes the program did not ask for.
    func testAFilterWeCannotHonourIsRefusedRatherThanIgnored() {
        for name in ["metadata", "template", "startedAfter", "order", "nextToken"] {
            let failure = try? XCTUnwrap(Self.failure(["\(name)": "x"]))
            XCTAssertEqual(failure?.status, 400, name)
            XCTAssertEqual(failure?.errorCode, SandboxApiCodes.unsupported, name)
        }
    }

    // MARK: timeout

    func testTimeoutZeroIsAllowedAndNegativeIsNot() throws {
        XCTAssertEqual(try SandboxApiTimeoutBody.parse(Data(#"{"timeout":0}"#.utf8)).timeoutSeconds, 0)
        XCTAssertThrowsError(try SandboxApiTimeoutBody.parse(Data(#"{"timeout":-1}"#.utf8)))
        XCTAssertThrowsError(try SandboxApiTimeoutBody.parse(Data(#"{"timeout":1.5}"#.utf8)))
        XCTAssertThrowsError(try SandboxApiTimeoutBody.parse(Data(#"{}"#.utf8)))
    }

    // MARK: connect

    func testAnEmptyConnectBodyMeansThreeHundredSeconds() throws {
        XCTAssertEqual(try SandboxApiConnectBody.parse(Data()).timeoutSeconds, 300)
        XCTAssertEqual(try SandboxApiConnectBody.parse(Data("{}".utf8)).timeoutSeconds, 300)
        XCTAssertEqual(try SandboxApiConnectBody.parse(Data(#"{"timeout":60}"#.utf8)).timeoutSeconds, 60)
    }

    func testARebootInsteadOfAResumeIsRefused() {
        XCTAssertThrowsError(try SandboxApiConnectBody.parse(Data(#"{"memory":false}"#.utf8)))
    }

    // MARK: state names

    func testTheApiCallsAPausedSandboxPausedAndEverythingElseRunning() {
        XCTAssertEqual(SandboxApiState.name(for: .paused), "paused")
        XCTAssertEqual(SandboxApiState.name(for: .running), "running")
        XCTAssertEqual(SandboxApiState.name(for: .starting), "running")
        XCTAssertEqual(SandboxApiState.name(for: .resuming), "running")
    }

    private static func failure(_ query: [String: String]) -> SandboxApiFailure? {
        do {
            _ = try SandboxApiListQuery.parse(query)
            return nil
        } catch let failure as SandboxApiFailure {
            return failure
        } catch {
            return nil
        }
    }
}
