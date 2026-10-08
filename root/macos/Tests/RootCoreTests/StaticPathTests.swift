import XCTest
@testable import RootCore

final class StaticPathTests: XCTestCase {
    func testRootIsTheIndexAndAssetsPass() {
        XCTAssertEqual(StaticPath.clean("/"), "index.html")
        XCTAssertEqual(StaticPath.clean("/assets/index-abc123.js"), "assets/index-abc123.js")
        XCTAssertEqual(StaticPath.clean("/favicon.svg"), "favicon.svg")
    }

    func testTraversalAndOddPathsAreRefused() {
        let bad = ["", "index.html", "/../etc/passwd", "/assets/../../x", "/.env", "/assets/.hidden", "//etc/passwd", "/a//b", "/a/", "/a b",
                   "/%2e%2e/x", "/a\\b", "/a\u{0}b", "/" + String(repeating: "a", count: 300), "/assets/x?y=1", "/assets/x#y", "/é"]
        for path in bad { XCTAssertNil(StaticPath.clean(path), path) }
    }

    func testContentTypes() {
        XCTAssertEqual(StaticPath.contentType(for: "a.js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(StaticPath.contentType(for: "a.CSS"), "text/css; charset=utf-8")
        XCTAssertNil(StaticPath.contentType(for: "a.exe"))
        XCTAssertNil(StaticPath.contentType(for: "noextension"))
        XCTAssertTrue(StaticPath.isHashedAsset("assets/a.js"))
        XCTAssertFalse(StaticPath.isHashedAsset("index.html"))
    }
}
