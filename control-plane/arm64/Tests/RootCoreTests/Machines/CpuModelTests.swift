import XCTest
@testable import RootCore

final class CpuModelTests: XCTestCase {
    private func model(_ value: Any?) throws -> String? {
        var body = RequestsTests.goodHeartbeat()
        var facts = body["facts"] as! [String: Any]
        if let value { facts["cpu_model"] = value }
        body["facts"] = facts
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: body)).facts.cpuModel
    }

    func testTheNameIsAcceptedAsTheHelperSaysIt() throws {
        XCTAssertEqual(try model("AMD Ryzen 9 5950X 16-Core Processor"), "AMD Ryzen 9 5950X 16-Core Processor")
        XCTAssertEqual(try model("Apple M4"), "Apple M4")
    }

    func testAnOlderHelperAndANullGiveNil() throws {
        XCTAssertNil(try model(nil))
        XCTAssertNil(try model(NSNull()))
    }

    func testControlCharactersAreRemovedAndSpacesCollapsed() throws {
        XCTAssertEqual(try model("  Intel(R)\tXeon(R)\u{0}  CPU \u{1B}[31m E5-2680   v4\n"), "Intel(R) Xeon(R) CPU [31m E5-2680 v4")
        XCTAssertNil(try model("  \t\n\u{0}  "))
        XCTAssertNil(try model(""))
    }

    func testALongNameIsCutToOneHundredTwentyCharacters() throws {
        XCTAssertEqual(CpuModelText.maxLength, 120)
        XCTAssertEqual(try model(String(repeating: "x", count: 300))?.count, 120)
        XCTAssertEqual(try model(String(repeating: "y", count: 120))?.count, 120)
    }

    func testMarkupIsKeptAsPlainTextForThePanelToShowAsText() throws {
        XCTAssertEqual(try model("<script>alert(1)</script> CPU"), "<script>alert(1)</script> CPU")
    }

    func testAWrongTypeOrAnAbsurdSizeIsRefused() {
        let bad: [Any] = [5, true, ["a"], String(repeating: "z", count: 5000)]
        for item in bad { XCTAssertThrowsError(try model(item), "\(item)") }
    }
}
