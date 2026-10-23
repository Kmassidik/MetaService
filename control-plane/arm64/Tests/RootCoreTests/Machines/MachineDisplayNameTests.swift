import XCTest
@testable import RootCore

final class MachineDisplayNameTests: XCTestCase {
    static let legal = ["Mac Studio", "Luca's PC (RTX)", "mac-mini", "R&D box_2.0", "Ünïcode Café", "1", "a", String(repeating: "x", count: 48)]
    static let refused = ["", " ", " lead", "trail ", "two  spaces", "a\tb", "line\nbreak", "nul\u{0}byte", "<b>x</b>", "a\"b", "a`b", "a$b", "a;b", "a/b", "a\\b", "a{b}", "a|b",
                          "a b\"c';rm -rf ~;", "...", "- - -", "😀", "Mac 😀", String(repeating: "x", count: 49), "a:b", "a=b", "a%b"]

    func testLegalNamesPass() {
        for name in Self.legal { XCTAssertNil(MachineDisplayName.problem(name), name) }
    }

    func testRefusedNamesGivePlainWords() {
        for name in Self.refused { XCTAssertNotNil(MachineDisplayName.problem(name), name.debugDescription) }
        XCTAssertEqual(MachineDisplayName.problem("a;b"), "Use letters, numbers, spaces and - _ . ( ) ' &, up to 48 characters.")
        XCTAssertEqual(MachineDisplayName.problem(""), "Give the machine a name.")
    }

    func testComparisonIgnoresCapitalsAndHowAnAccentIsWritten() {
        XCTAssertEqual(MachineDisplayName.comparable("Mac Studio"), MachineDisplayName.comparable("mac STUDIO"))
        XCTAssertEqual(MachineDisplayName.comparable("Caf\u{e9}"), MachineDisplayName.comparable("Cafe\u{301}"))
        XCTAssertNotEqual(MachineDisplayName.comparable("Mac Studio"), MachineDisplayName.comparable("Mac-Studio"))
    }
}
