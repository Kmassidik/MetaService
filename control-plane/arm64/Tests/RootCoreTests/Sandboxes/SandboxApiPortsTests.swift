import Foundation
import XCTest
@testable import RootCore

/// `POST /v2/sandboxes/{sandboxID}/ports`: the body and the reply of the public API.
final class SandboxApiPortsTests: XCTestCase {
    private func refusal(_ body: String) -> SandboxApiFailure? {
        do {
            _ = try SandboxApiPortBody.parse(Data(body.utf8))
            return nil
        } catch let failure as SandboxApiFailure {
            return failure
        } catch {
            return nil
        }
    }

    func testAPortIsOpenedByItsNumber() throws {
        XCTAssertEqual(try SandboxApiPortBody.parse(Data(#"{"port":8080}"#.utf8)), SandboxApiPortBody(port: 8080))
        XCTAssertEqual(try SandboxApiPortBody.parse(Data(#"{"port":1}"#.utf8)).port, 1)
        XCTAssertEqual(try SandboxApiPortBody.parse(Data(#"{"port":65535}"#.utf8)).port, 65535)
    }

    func testAPortOutsideTheRangeIsABadRequest() {
        for body in [#"{"port":0}"#, #"{"port":65536}"#, #"{"port":-1}"#, #"{"port":8080.5}"#, #"{"port":"8080"}"#, #"{"port":null}"#] {
            XCTAssertEqual(refusal(body)?.status, 400, body)
            XCTAssertEqual(refusal(body)?.errorCode, SandboxApiCodes.invalidRequest, body)
        }
    }

    func testTheBodyHoldsThePortAndNothingElse() {
        XCTAssertEqual(refusal(#"{"port":8080,"path":"/"}"#)?.status, 400)
        XCTAssertEqual(refusal(#"{}"#)?.status, 400)
        XCTAssertEqual(refusal("not json")?.status, 400)
        XCTAssertEqual(refusal("[]")?.status, 400)
    }

    func testTheReplyNamesTheHostTheTokenAndItsExpiry() throws {
        let reply = SandboxApiPort(host: "6dq5fq5uuwlio6dj.ruvio.site", token: "v1.token", expiresAt: "2026-10-25T12:15:00Z")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["host", "token", "expiresAt"])
        XCTAssertEqual(json["host"] as? String, "6dq5fq5uuwlio6dj.ruvio.site")
        XCTAssertEqual(json["expiresAt"] as? String, "2026-10-25T12:15:00Z")
    }
}
