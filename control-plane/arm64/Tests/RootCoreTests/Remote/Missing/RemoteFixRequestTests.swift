import XCTest
@testable import RootCore

final class RemoteFixRequestTests: XCTestCase {
    private let base: [String: Any] = ["host": "192.168.100.40", "user": "build", "fingerprint": "SHA256:" + String(repeating: "A", count: 43), "use_key": true, "fix": "vm_tool", "sudo_password": "Fake-Pass-9f3a"]

    private func request(_ changes: [String: Any] = [:]) throws -> RemoteFixRequest {
        try RemoteFixRequest(body: JSONSerialization.data(withJSONObject: base.merging(changes) { $1 }))
    }

    func testItHasTheLoginThePartAndThePassword() throws {
        let value = try request()
        XCTAssertEqual(value.login, .parentKey)
        guard case .typed(let target, _) = value.target else { return XCTFail("a typed address") }
        XCTAssertEqual(target.user, "build")
        XCTAssertEqual(value.part, .vmTool)
        XCTAssertEqual(value.sudoPassword.standardInput(), Data("Fake-Pass-9f3a\n".utf8))
        XCTAssertFalse("\(value)".contains("Fake-Pass-9f3a"), "printing the request must not show the password")
    }

    func testTheSudoPasswordMayBeLeftOutForALoginThatNeedsNone() throws {
        let value = try RemoteFixRequest(body: JSONSerialization.data(withJSONObject: base.filter { $0.key != "sudo_password" }))
        XCTAssertTrue(value.sudoPassword.isEmpty)
    }

    func testOnlyKnownPartsAndFieldsPass() {
        XCTAssertThrowsError(try request(["fix": "rm -rf"]))
        XCTAssertThrowsError(try request(["fix": ""]))
        XCTAssertThrowsError(try request(["extra": 1]))
        XCTAssertThrowsError(try request(["sudo_password": String(repeating: "x", count: 257)]))
        XCTAssertNoThrow(try request(["fix": "python"]))
    }

    func testTheLoginRulesOfConnectStillApply() {
        XCTAssertThrowsError(try request(["use_key": false]), "neither a password nor the key")
        XCTAssertThrowsError(try request(["password": "x"]), "both a password and the key")
        XCTAssertThrowsError(try request(["user": "a;b"]))
        XCTAssertNoThrow(try request(["use_key": false, "password": "login-pass"]))
    }
}
