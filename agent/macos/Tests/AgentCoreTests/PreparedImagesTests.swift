import XCTest
@testable import AgentCore

final class PreparedImagesTests: XCTestCase {
    func testOnlyTheStockImageIsListedAndItIsReady() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: PreparedImages.stockOnly) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["images"])
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["id"] as? String, "blank")
        XCTAssertEqual(images[0]["ready"] as? Bool, true)
        XCTAssertTrue(images[0]["built_at"] is NSNull, "the stock image has no build time")
        XCTAssertEqual(Set(images[0].keys), ["id", "ready", "built_at"])
    }
}
