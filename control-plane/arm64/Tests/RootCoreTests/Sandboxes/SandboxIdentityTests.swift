import Foundation
import XCTest
@testable import RootCore

final class SandboxIdentityTests: XCTestCase {
    func testANewIdIsTwentyLowercaseLettersAndDigits() {
        for _ in 0..<200 {
            let id = SandboxIdentity.newId()
            XCTAssertEqual(id.count, SandboxIdentity.idCharacters)
            XCTAssertTrue(SandboxIdentity.isValid(id), id)
        }
    }

    func testIdsThatAreNotShapedLikeOursAreRefused() {
        XCTAssertFalse(SandboxIdentity.isValid(""))
        XCTAssertFalse(SandboxIdentity.isValid("AAAAAAAAAAAAAAAAAAAA"))
        XCTAssertFalse(SandboxIdentity.isValid("aaaaaaaaaaaaaaaaaaaaa"))
        XCTAssertFalse(SandboxIdentity.isValid("aaaaaaaa-aaaaaaaaaaa"))
        XCTAssertFalse(SandboxIdentity.isValid("../../etc/passwd0000"))
    }
}
