import Foundation
import XCTest
@testable import RootCore

final class SandboxApiRepliesTests: XCTestCase {
    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        guard let object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] else { return [:] }
        return object
    }

    /// The domain is a setting, so the same create answers with the domain the Root was configured for, never a literal.
    func testTheDomainComesFromTheCallerNotFromTheCode() throws {
        let one = try encoded(SandboxApiSandbox(templateID: "base", sandboxID: "aaaaaaaaaaaaaaaaaaaa", envdVersion: "0.10.2",
                                                envdAccessToken: "token", domain: "sandbox.example.com"))
        let other = try encoded(SandboxApiSandbox(templateID: "base", sandboxID: "aaaaaaaaaaaaaaaaaaaa", envdVersion: "0.10.2",
                                                  envdAccessToken: "token", domain: "sbx.test"))
        XCTAssertEqual(one["domain"] as? String, "sandbox.example.com")
        XCTAssertEqual(other["domain"] as? String, "sbx.test")
    }

    /// The six fields a create must answer with, in the SDK's capitalisation, and nothing else.
    func testACreateReplyHasExactlyTheSixFieldsTheSdkReads() throws {
        let body = try encoded(SandboxApiSandbox(templateID: "base", sandboxID: "aaaaaaaaaaaaaaaaaaaa", envdVersion: "0.10.2",
                                                 envdAccessToken: "token", domain: "sandbox.example.com"))
        XCTAssertEqual(Set(body.keys), ["templateID", "sandboxID", "clientID", "envdVersion", "envdAccessToken", "domain"])
        XCTAssertEqual(body["clientID"] as? String, SandboxApiDefaults.clientID)
        XCTAssertEqual(body["envdAccessToken"] as? String, "token")
    }

    func testADetailCarriesTheRecordAndTheSettings() throws {
        let detail = SandboxApiDetail(templateID: "base", sandboxID: "aaaaaaaaaaaaaaaaaaaa", startedAt: "2026-10-24T09:00:00Z",
                                      endAt: "2026-10-24T09:05:00Z", cpuCount: 2, memoryMB: 512, diskSizeMB: 10_240,
                                      envdVersion: "0.10.2", domain: "sandbox.example.com", state: "running")
        let body = try encoded(detail)
        XCTAssertEqual(body["domain"] as? String, "sandbox.example.com")
        XCTAssertEqual(body["cpuCount"] as? Int, 2)
        XCTAssertEqual(body["memoryMB"] as? Int, 512)
        XCTAssertEqual(body["allowInternetAccess"] as? Bool, false)
        XCTAssertEqual((body["lifecycle"] as? [String: Any])?["onTimeout"] as? String, "kill")
        XCTAssertEqual((body["volumeMounts"] as? [Any])?.count, 0)
        XCTAssertEqual(body["metadata"] as? [String: String], [:])
    }

    func testAnErrorRepeatsTheStatusAndCarriesItsCode() throws {
        let body = try encoded(SandboxApiErrorBody(SandboxApiFailure.noRoom(SandboxPlacementRefusal(
            code: "not_enough_room", message: "No machine has room.", resource: "ram_mb", needed: 512, free: 0))))
        XCTAssertEqual(body["code"] as? Int, 503)
        XCTAssertEqual(body["message"] as? String, "No machine has room.")
        XCTAssertEqual(body["error_code"] as? String, SandboxApiCodes.noRoom)
    }

    func testTheTeamLimitMappingFollowsTheApi() {
        let atOnce = SandboxApiFailure.teamLimit(TeamLimitRefusal(reason: .tooManyRunning, message: "full", limit: 1, used: 1, needed: 1))
        XCTAssertEqual(atOnce.status, 429)
        let memory = SandboxApiFailure.teamLimit(TeamLimitRefusal(reason: .tooMuchRam, message: "big", limit: 1, used: 1, needed: 1))
        XCTAssertEqual(memory.status, 403)
    }

    func testTheHelperMappingNeverTurnsAFailureIntoA500() {
        XCTAssertEqual(SandboxApiFailure.helper(status: 504, errorCode: "start_timeout", message: nil).status, 503)
        XCTAssertEqual(SandboxApiFailure.helper(status: 404, errorCode: nil, message: nil).status, 503)
        XCTAssertEqual(SandboxApiFailure.helper(status: 409, errorCode: "not_enough_room", message: nil).status, 409)
        XCTAssertEqual(SandboxApiFailure.helper(status: 500, errorCode: nil, message: nil).status, 503)
        XCTAssertEqual(SandboxApiFailure.helperUnreachable.status, 503)
    }

    func testOnlyAPlainVersionIsReported() {
        XCTAssertTrue(SandboxApiDefaults.isVersion("0.10.2"))
        XCTAssertFalse(SandboxApiDefaults.isVersion("v0.10.2"))
        XCTAssertFalse(SandboxApiDefaults.isVersion("0.10"))
        XCTAssertFalse(SandboxApiDefaults.isVersion(""))
    }
}
