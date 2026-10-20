import XCTest
@testable import RootCore

final class SshErrorsTests: XCTestCase {
    private func kind(_ errors: String, status: Int32 = 255) -> SshErrorKind { SshErrors.classify(status: status, errors: errors) }

    func testARefusedLoginIsRecognised() {
        XCTAssertEqual(kind("mac@127.0.0.1: Permission denied (publickey)."), .loginRefused)
        XCTAssertEqual(kind("Permission denied, please try again."), .loginRefused)
    }

    func testAServerThatListsOnlyKeysTakesNoPasswords() {
        XCTAssertTrue(SshErrors.offersOnlyKeys("lucacadalora@192.168.0.10: Permission denied (publickey)."))
        XCTAssertTrue(SshErrors.offersOnlyKeys("Permission denied (publickey,gssapi-with-mic)."))
        XCTAssertFalse(SshErrors.offersOnlyKeys("Permission denied (publickey,password)."))
        XCTAssertFalse(SshErrors.offersOnlyKeys("Permission denied (publickey,keyboard-interactive)."))
        XCTAssertFalse(SshErrors.offersOnlyKeys("Permission denied, please try again."))
        XCTAssertFalse(SshErrors.offersOnlyKeys(""))
    }

    func testAChangedHostKeyIsRecognised() {
        XCTAssertEqual(kind("@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@"), .hostKeyChanged)
        XCTAssertEqual(kind("Host key verification failed."), .hostKeyChanged)
    }

    func testAnUnreachableComputerIsRecognised() {
        for text in ["ssh: connect to host 10.0.0.9 port 22: Connection refused", "ssh: connect to host 10.0.0.9 port 22: No route to host", "Connection timed out during banner exchange",
                     "ssh: Could not resolve hostname nope", "ssh: connect to host 10.0.0.9 port 22: Operation timed out", "Network is unreachable"] {
            XCTAssertEqual(kind(text), .unreachable, text)
        }
    }

    func testAServerThatJustDropsTheConnectionIsRecognisedEvenWhenSshSaysNothing() {
        XCTAssertEqual(kind("", status: 255), .closed, "OpenSSH drops an address after failed logins and ssh prints nothing")
        XCTAssertEqual(kind("   \n", status: 255), .closed)
        XCTAssertEqual(kind("Connection closed by 10.0.0.9 port 22"), .closed)
        XCTAssertEqual(kind("kex_exchange_identification: read: Connection reset by peer"), .closed)
        XCTAssertEqual(kind("client_loop: send disconnect: Broken pipe"), .closed)
    }

    func testAnythingElseIsOther() {
        XCTAssertEqual(kind("something odd happened"), .other)
        XCTAssertEqual(kind("", status: 1), .other, "an empty answer with an ordinary failure status is not a dropped connection")
    }

    func testARefusalWinsOverAnEmptyLookingText() {
        XCTAssertEqual(kind("Permission denied (publickey).\nConnection closed by 10.0.0.9"), .loginRefused)
    }
}
