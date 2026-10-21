import XCTest
@testable import AgentCore

final class TerminalFramesTests: XCTestCase {
    func testResizeAcceptsTheBoundsExactly() {
        XCTAssertEqual(TerminalFrames.parseResize(#"{"resize":[80,24]}"#), TerminalSize(cols: 80, rows: 24))
        XCTAssertEqual(TerminalFrames.parseResize(#"{"resize":[1,1]}"#), TerminalSize(cols: 1, rows: 1))
        XCTAssertEqual(TerminalFrames.parseResize(#"{"resize":[500,300]}"#), TerminalSize(cols: 500, rows: 300))
    }

    func testResizeRefusesEverythingElse() {
        let bad = [#"{"resize":[0,24]}"#, #"{"resize":[501,24]}"#, #"{"resize":[80,0]}"#, #"{"resize":[80,301]}"#, #"{"resize":[-1,24]}"#,
                   #"{"resize":[80]}"#, #"{"resize":[80,24,1]}"#, #"{"resize":["80","24"]}"#, #"{"resize":[80.5,24]}"#, #"{"resize":[true,true]}"#,
                   #"{"resize":[80,24],"x":1}"#, #"{"other":[80,24]}"#, #"[80,24]"#, "hello", "", #"{"resize":[1e9,24]}"#,
                   #"{"resize":[80,24]}"# + String(repeating: " ", count: 100)]
        for text in bad { XCTAssertNil(TerminalFrames.parseResize(text), text) }
    }

    func testInputFrameCapIsExact() {
        XCTAssertEqual(TerminalFrames.input(binary: [UInt8](repeating: 97, count: 65536)), .keys([UInt8](repeating: 97, count: 65536)))
        XCTAssertEqual(TerminalFrames.input(binary: [UInt8](repeating: 97, count: 65537)), .refused, "one byte over is refused")
        XCTAssertEqual(TerminalFrames.input(binary: []), .keys([]))
    }

    func testTextFramesAreResizeOrRefused() {
        XCTAssertEqual(TerminalFrames.input(text: #"{"resize":[100,30]}"#), .resize(TerminalSize(cols: 100, rows: 30)))
        XCTAssertEqual(TerminalFrames.input(text: "ls -la\n"), .refused, "typed text must travel as binary, never as text")
    }

    func testCloseReasons() {
        XCTAssertEqual(ConsoleClose.shellEnded.code, 1000)
        XCTAssertEqual(ConsoleClose.shellEnded.reason, "the shell ended")
        for refusal in [ConsoleClose.badFrame, .alreadyOpen, .couldNotStart] { XCTAssertEqual(refusal.code, 1008) }
    }
}
