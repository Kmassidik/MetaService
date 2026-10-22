import XCTest
@testable import MSCore

final class UntrustedTextTests: XCTestCase {
    func testColourAndCursorSequencesAreRemoved() {
        XCTAssertEqual(UntrustedText.tail("\u{1B}[31mred\u{1B}[0m ok\u{1B}[2J", lines: 12, maxBytes: 2048), "red ok")
        XCTAssertEqual(UntrustedText.tail("a\u{1B}]0;title\u{07}b\u{1B}]8;;http://x\u{1B}\\c", lines: 12, maxBytes: 2048), "abc")
        XCTAssertEqual(UntrustedText.tail("a\u{1B}Mb", lines: 12, maxBytes: 2048), "ab")
    }

    func testOtherControlCharactersAreRemovedButLinesStay() {
        XCTAssertEqual(UntrustedText.tail("one\r\ntwo\u{00}\u{07}\u{7F}\u{85}\nthree\tx", lines: 12, maxBytes: 2048), "one\ntwo\nthree x")
    }

    func testOnlyTheLastLinesStay() {
        let text = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let tail = UntrustedText.tail(text, lines: 12, maxBytes: 2048)
        XCTAssertEqual(tail.split(separator: "\n").count, 12)
        XCTAssertTrue(tail.hasPrefix("line 19"))
        XCTAssertTrue(tail.hasSuffix("line 30"))
    }

    func testTheCapCutsTheStartAndNeverBreaksACharacter() {
        let text = String(repeating: "é", count: 3000)
        let tail = UntrustedText.tail(text, lines: 12, maxBytes: 2048)
        XCTAssertLessThanOrEqual(tail.utf8.count, 2048)
        XCTAssertTrue(tail.allSatisfy { $0 == "é" })
        XCTAssertEqual(UntrustedText.tail("", lines: 12, maxBytes: 2048), "")
    }

    func testBytesThatAreNotUTF8BecomeReplacementCharacters() {
        let data = Data([0x68, 0x69, 0xFF, 0xFE, 0x0A])
        XCTAssertEqual(UntrustedText.tail(data, lines: 12, maxBytes: 2048), "hi\u{FFFD}\u{FFFD}")
    }

    func testMarkupStaysTextAndIsNotChanged() {
        XCTAssertEqual(UntrustedText.tail("<img src=x onerror=alert(1)>", lines: 12, maxBytes: 2048), "<img src=x onerror=alert(1)>")
    }
}
