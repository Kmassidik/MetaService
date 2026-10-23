import XCTest
@testable import AgentCore

final class PreparedImagesTests: XCTestCase {
    private func images() throws -> [[String: Any]] {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: PreparedImages.list) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["images"])
        return try XCTUnwrap(json["images"] as? [[String: Any]])
    }

    func testTheStockImageIsListedFirstAndItIsReady() throws {
        let stock = try XCTUnwrap(images().first)
        XCTAssertEqual(stock["id"] as? String, "blank")
        XCTAssertEqual(stock["ready"] as? Bool, true)
        XCTAssertTrue(stock["built_at"] is NSNull, "the stock image has no build time")
        XCTAssertEqual(Set(stock.keys), ["id", "ready", "built_at"])
    }

    func testTheTwoAppsAreReadyWithTheInstallCaption() throws {
        let listed = try images()
        XCTAssertEqual(listed.compactMap { $0["id"] as? String }, ["blank", "openclaw", "hermes"])
        for entry in listed.dropFirst() {
            XCTAssertEqual(entry["ready"] as? Bool, true)
            XCTAssertEqual(entry["caption"] as? String, "Installs after the VM starts, about 2 minutes")
        }
    }
}
