import XCTest
@testable import RootCore

final class ShellTests: XCTestCase {
    private func shown(_ text: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s " + Shell.quote(text)]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testAnyTextComesBackExactlyAsOneWord() throws {
        for text in ["plain", "with space", "it's", "'''", "$HOME", "`id`", "$(id)", "a;b", "a|b&c", "a\nb", "tab\there", "\"double\"", "back\\slash", "*", "~", "-n", "", "ünïcödé ✓"] {
            XCTAssertEqual(try shown(text), text, text)
        }
    }

    func testTheQuoteIsASingleQuotedWord() {
        XCTAssertEqual(Shell.quote("abc"), "'abc'")
        XCTAssertEqual(Shell.quote("it's"), "'it'\\''s'")
        XCTAssertEqual(Shell.quote(""), "''")
    }
}
