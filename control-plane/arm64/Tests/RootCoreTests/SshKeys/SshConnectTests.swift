import MSCore
import XCTest
@testable import RootCore

final class SshConnectTests: XCTestCase {
    func testTheDefaultJumpComesFromTheOfficeAddressOfTheMachine() {
        XCTAssertEqual(SshConnect.defaultJump(user: "lucacadalora", host: "192.168.1.20", port: 22), "lucacadalora@192.168.1.20")
        XCTAssertEqual(SshConnect.defaultJump(user: "kurnia", host: "studio.example.com", port: 2222), "kurnia@studio.example.com:2222")
    }

    func testAHostileOrBrokenOfficeAddressGivesNoDefault() {
        XCTAssertNil(SshConnect.defaultJump(user: "a b", host: "192.168.1.20", port: 22))
        XCTAssertNil(SshConnect.defaultJump(user: "kurnia", host: "host;rm -rf /", port: 22))
        XCTAssertNil(SshConnect.defaultJump(user: "kurnia", host: "-oProxyCommand=x", port: 22))
        XCTAssertNil(SshConnect.defaultJump(user: "kurnia", host: "192.168.1.20", port: 0))
        XCTAssertNil(SshConnect.defaultJump(user: "kurnia", host: "192.168.1.20", port: 70_000))
    }

    func testAJumpIsUserAtHostWithAnOptionalPort() {
        for good in ["you@203.0.113.7", "you@studio.example.com:2222", "a.b-c_d@host-1.example", "me@10.0.0.1:65535"] {
            XCTAssertTrue(SshConnect.isValidJump(good), good)
        }
        for bad in ["", "host", "@host", "you@", "you@host:", "you@host:0", "you@host:65536", "you@host:123456", "you@ho st", "you@host;id", "you@$(id)", "you@host\nid",
                    "-o x@host", "you@host:22:22", "you@host/x", String(repeating: "a", count: 119) + "@h"] {
            XCTAssertFalse(SshConnect.isValidJump(bad), bad.debugDescription)
        }
    }

    func testTheCommandJumpsThroughTheMachineToTheVm() {
        XCTAssertEqual(SshConnect.command(jump: "you@203.0.113.7", vmAddress: "192.168.64.5"), "ssh -J you@203.0.113.7 root@192.168.64.5")
        XCTAssertEqual(SshConnect.command(jump: "you@studio.example.com:2222", vmAddress: "10.0.0.7"), "ssh -J you@studio.example.com:2222 root@10.0.0.7")
        XCTAssertEqual(SshConnect.command(jump: "you@h", vmAddress: "fd00::1234"), "ssh -J you@h root@fd00::1234")
        XCTAssertEqual(SshConnect.command(jump: "you@h", vmAddress: "vm-1.lan"), "ssh -J you@h root@vm-1.lan")
    }

    func testTheSettingWinsOverTheOfficeAddress() {
        let office = (user: "kurnia", host: "192.168.1.20", port: 22)
        XCTAssertEqual(SshConnect.resolveJump(setting: "you@h:2222", office: office).jump, "you@h:2222")
        XCTAssertFalse(SshConnect.resolveJump(setting: "you@h:2222", office: office).isDefault)
        let fallback = SshConnect.resolveJump(setting: nil, office: office)
        XCTAssertEqual(fallback.jump, "kurnia@192.168.1.20")
        XCTAssertTrue(fallback.isDefault)
        XCTAssertEqual(SshConnect.resolveJump(setting: nil, office: (user: "kurnia", host: "192.168.1.20", port: 2222)).jump, "kurnia@192.168.1.20:2222")
    }

    func testAnUnusableSettingFallsBackAndNothingAtAllGivesNoJump() {
        let office = (user: "kurnia", host: "192.168.1.20", port: 22)
        XCTAssertEqual(SshConnect.resolveJump(setting: "bad value", office: office).jump, "kurnia@192.168.1.20")
        XCTAssertNil(SshConnect.resolveJump(setting: nil, office: nil).jump)
        XCTAssertFalse(SshConnect.resolveJump(setting: nil, office: nil).isDefault)
        XCTAssertNil(SshConnect.resolveJump(setting: nil, office: (user: "a b", host: "h", port: 22)).jump)
    }

    func testNoCommandWithoutBothPartsOrWithAnythingOdd() {
        XCTAssertNil(SshConnect.command(jump: nil, vmAddress: "10.0.0.7"))
        XCTAssertNil(SshConnect.command(jump: "you@h", vmAddress: nil))
        XCTAssertNil(SshConnect.command(jump: "you@h; reboot", vmAddress: "10.0.0.7"))
        for hostile in ["10.0.0.7; id", "10.0.0.7 -oProxyCommand=x", "$(id)", "`id`", "a'b", "a\"b", "10.0.0.7\n", "-10.0.0.7", "", ":::", "1:2", "...", String(repeating: "a", count: 254)] {
            XCTAssertNil(SshConnect.command(jump: "you@h", vmAddress: hostile), hostile.debugDescription)
        }
    }
}
