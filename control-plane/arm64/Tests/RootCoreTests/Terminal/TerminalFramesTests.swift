import XCTest
@testable import RootCore

final class TerminalFramesTests: XCTestCase {
    func testInputUpToTheLimitPassesAndOneByteMoreIsRefused() {
        XCTAssertNil(TerminalFrames.checkInput(byteCount: 0))
        XCTAssertNil(TerminalFrames.checkInput(byteCount: 65_536))
        XCTAssertEqual(TerminalFrames.checkInput(byteCount: 65_537)?.code, 1008)
    }

    func testResizeInsideTheBoundsPasses() {
        XCTAssertNil(TerminalFrames.checkResize(text: #"{"resize":[80,24]}"#))
        XCTAssertNil(TerminalFrames.checkResize(text: #"{"resize":[1,1]}"#))
        XCTAssertNil(TerminalFrames.checkResize(text: #"{"resize":[500,300]}"#))
    }

    func testResizeOutsideTheBoundsClosesWith1008() {
        for text in [#"{"resize":[0,24]}"#, #"{"resize":[80,0]}"#, #"{"resize":[501,24]}"#, #"{"resize":[80,301]}"#, #"{"resize":[-1,24]}"#] {
            XCTAssertEqual(TerminalFrames.checkResize(text: text)?.code, 1008, text)
        }
    }

    func testAnyOtherTextIsRefused() {
        let hostile = ["", "hello", "{}", #"{"resize":[80]}"#, #"{"resize":[80,24,1]}"#, #"{"resize":["80","24"]}"#, #"{"resize":[80.5,24]}"#,
                       #"{"resize":[80,24],"cmd":"rm"}"#, #"{"cmd":"ls"}"#, #"[80,24]"#, #"{"resize":null}"#,
                       #"{"resize":[80,24]}"# + String(repeating: " ", count: 100)]
        for text in hostile {
            XCTAssertEqual(TerminalFrames.checkResize(text: text), .badFrame, text)
        }
    }

    func testCloseReasonsFollowTheContract() {
        XCTAssertEqual(CloseReason.shellEnded, CloseReason(code: 1000, text: "the shell ended"))
        XCTAssertEqual(CloseReason.idle, CloseReason(code: 1000, text: "idle for 15 minutes"))
        XCTAssertEqual(CloseReason.vmStopped, CloseReason(code: 1000, text: "the VM stopped"))
        XCTAssertEqual(CloseReason.machineOffline, CloseReason(code: 1011, text: "the machine is offline"))
        XCTAssertEqual(CloseReason.badFrame.code, 1008)
        let all: [CloseReason] = [.shellEnded, .idle, .tooLong, .vmStopped, .vmDeleted, .machineRemoved, .machineOffline, .vmUnavailable, .badFrame]
        XCTAssertTrue(all.allSatisfy { $0.text.utf8.count <= 123 })
    }
}
