import Foundation
import XCTest
@testable import RootCore

final class SandboxApiAuthTests: XCTestCase {
    private func headers(bearer: String? = nil, apiKey: String? = nil, cookies: Bool = false) -> SandboxApiHeaders {
        SandboxApiHeaders(authorization: bearer.map { "Bearer \($0)" }, apiKey: apiKey, hasCookies: cookies)
    }

    private func refusal(_ headers: SandboxApiHeaders, file: StaticString = #filePath, line: UInt = #line) -> SandboxApiFailure? {
        do {
            _ = try SandboxApiAuth.presentedKey(headers)
            return nil
        } catch let failure as SandboxApiFailure {
            return failure
        } catch {
            XCTFail("not a SandboxApiFailure: \(error)", file: file, line: line)
            return nil
        }
    }

    func testABearerKeyIsAccepted() throws {
        XCTAssertEqual(try SandboxApiAuth.presentedKey(headers(bearer: "msb_ab12cd34_secret")), "msb_ab12cd34_secret")
    }

    func testXApiKeyIsAcceptedOnItsOwn() throws {
        XCTAssertEqual(try SandboxApiAuth.presentedKey(headers(apiKey: "msb_ab12cd34_secret")), "msb_ab12cd34_secret")
    }

    func testTheSameKeyInBothHeadersIsAccepted() throws {
        XCTAssertEqual(try SandboxApiAuth.presentedKey(headers(bearer: "same", apiKey: "same")), "same")
    }

    func testTwoDifferentKeysInBothHeadersAreRefused() {
        let answer = refusal(headers(bearer: "one", apiKey: "two"))
        XCTAssertEqual(answer?.status, 401)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.invalidKey)
    }

    func testNoKeyAtAllIs401() {
        let answer = refusal(headers())
        XCTAssertEqual(answer?.status, 401)
        XCTAssertEqual(answer?.message.isEmpty, false)
    }

    func testAKeyThatIsNotABearerTokenIsIgnored() {
        let answer = refusal(SandboxApiHeaders(authorization: "Basic Zm9vOmJhcg==", apiKey: nil, hasCookies: false))
        XCTAssertEqual(answer?.status, 401)
    }

    func testAnEmptyOrOverlongKeyIs401() {
        XCTAssertEqual(refusal(headers(apiKey: ""))?.status, 401)
        let long = String(repeating: "a", count: SandboxApiAuth.maximumKeyCharacters + 1)
        XCTAssertEqual(refusal(headers(apiKey: long))?.status, 401)
    }

    /// The confused-deputy case: a browser's session cookie must never stand in for a program's key, even next to a good one.
    func testACookieBearingRequestIsRefusedEvenWithAGoodKey() {
        let answer = refusal(headers(apiKey: "msb_ab12cd34_secret", cookies: true))
        XCTAssertEqual(answer?.status, 401)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.sessionCookie)
    }

    func testTheRefusalNeverRepeatsTheKey() {
        let key = "msb_ab12cd34_do-not-echo-me"
        let answer = refusal(headers(apiKey: key, cookies: true))
        XCTAssertFalse(answer?.message.contains("do-not-echo-me") ?? true)
    }
}
