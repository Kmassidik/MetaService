import Foundation
import XCTest
@testable import RootCore

final class SandboxApiCreateBodyTests: XCTestCase {
    private func spec(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> SandboxCreateSpec {
        try SandboxApiCreateBody.parse(object)
    }

    private func failure(_ object: [String: Any]) -> SandboxApiFailure? {
        do {
            _ = try SandboxApiCreateBody.parse(object)
            return nil
        } catch let failure as SandboxApiFailure {
            return failure
        } catch {
            return nil
        }
    }

    func testARequestWithOnlyATemplateUsesTheDefaultTimeout() throws {
        let parsed = try spec(["templateID": "base"])
        XCTAssertEqual(parsed.template, "base")
        XCTAssertEqual(parsed.timeoutSeconds, 300)
        XCTAssertEqual(parsed.envVars, [:])
    }

    func testEveryFieldTheSdkSendsIsAccepted() throws {
        let parsed = try spec(["templateID": "base-1", "timeout": 600, "autoPause": false, "autoPauseMemory": true,
                               "autoResume": ["enabled": false], "allow_internet_access": false,
                               "envVars": ["A": "1", "_b": "two"], "network": ["allowPublicTraffic": true],
                               "volumeMounts": [Any]()])
        XCTAssertEqual(parsed.timeoutSeconds, 600)
        XCTAssertEqual(parsed.envVars, ["A": "1", "_b": "two"])
    }

    func testTheTemplateIsRequiredAndMustBeShapedLikeOne() {
        XCTAssertEqual(failure([:])?.status, 400)
        XCTAssertEqual(failure(["templateID": "Base"])?.status, 400)
        XCTAssertEqual(failure(["templateID": "-base"])?.status, 400)
        XCTAssertEqual(failure(["templateID": "a" + String(repeating: "b", count: 64)])?.status, 400)
    }

    func testAnUnknownFieldIsRefusedRatherThanIgnored() {
        let answer = failure(["templateID": "base", "somethingNew": true])
        XCTAssertEqual(answer?.status, 400)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.invalidRequest)
    }

    func testASettingWeDoNotSupportIsRefusedByItsName() {
        let refused: [[String: Any]] = [
            ["templateID": "base", "autoPause": true],
            ["templateID": "base", "autoPauseMemory": false],
            ["templateID": "base", "autoResume": ["enabled": true]],
            ["templateID": "base", "allow_internet_access": true],
            ["templateID": "base", "network": ["denyOut": ["1.2.3.4"]]],
            ["templateID": "base", "iam": ["role": "x"]],
            ["templateID": "base", "mcp": ["servers": []]],
            ["templateID": "base", "volumeMounts": [["name": "v"]]],
            ["templateID": "base", "metadata": ["run": "42"]],
        ]
        for object in refused {
            let answer = failure(object)
            XCTAssertEqual(answer?.status, 400, "\(object) was not refused")
            XCTAssertEqual(answer?.errorCode, SandboxApiCodes.unsupported, "\(object) gave the wrong code")
        }
    }

    func testTimeoutMustBeAWholeNumberOfSeconds() {
        XCTAssertEqual(failure(["templateID": "base", "timeout": 0])?.status, 400)
        XCTAssertEqual(failure(["templateID": "base", "timeout": -5])?.status, 400)
        XCTAssertEqual(failure(["templateID": "base", "timeout": 1.5])?.status, 400)
        XCTAssertEqual(failure(["templateID": "base", "timeout": "300"])?.status, 400)
    }

    func testEnvironmentVariableNamesAreChecked() {
        XCTAssertEqual(failure(["templateID": "base", "envVars": ["1A": "x"]])?.status, 400)
        XCTAssertEqual(failure(["templateID": "base", "envVars": ["A-B": "x"]])?.status, 400)
        XCTAssertEqual(failure(["templateID": "base", "envVars": ["A": 1]])?.status, 400)
    }

    func testABodyThatIsNotAnObjectIs400() {
        XCTAssertThrowsError(try SandboxApiCreateBody.parse(Data("[]".utf8)))
        XCTAssertThrowsError(try SandboxApiCreateBody.parse(Data("not json".utf8)))
    }
}
