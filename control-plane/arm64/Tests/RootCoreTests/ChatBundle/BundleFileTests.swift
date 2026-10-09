import XCTest
@testable import RootCore

final class BundleFileTests: XCTestCase {
    func testGoodNames() {
        XCTAssertEqual(BundleFile(fileName: "metaservice-chat-0.1.0-noarch.tar.gz"), BundleFile(fileName: "metaservice-chat-0.1.0-noarch.tar.gz"))
        XCTAssertEqual(BundleFile(fileName: "metaservice-chat-12.3.45-linux-aarch64.tar.gz")?.platform, "linux-aarch64")
        XCTAssertEqual(BundleFile(fileName: "metaservice-chat-1.0.0-macos-arm64.tar.gz")?.version, "1.0.0")
        XCTAssertEqual(BundleFile.fileName(version: "1.2.3", platform: "noarch"), "metaservice-chat-1.2.3-noarch.tar.gz")
    }

    func testBadNamesAreNotBundles() {
        for bad in ["", "metaservice-chat-1.0-noarch.tar.gz", "metaservice-chat-1.0.0-noarch.tgz", "metaservice-chat-1.0.0-windows-x86_64.tar.gz", "../metaservice-chat-1.0.0-noarch.tar.gz",
                    "metaservice-chat-1.0.0-noarch.tar.gz/x", "x-metaservice-chat-1.0.0-noarch.tar.gz", "metaservice-chat-1.0.0-noarch.tar.gz ", "metaservice-chat-1.0.0-noarch.tar.gz\n",
                    "metaservice-chat-v1.0.0-noarch.tar.gz", "metaservice-chat-1.0.0;reboot-noarch.tar.gz", "metaservice-chat-99999.0.0-noarch.tar.gz"] {
            XCTAssertNil(BundleFile(fileName: bad), bad)
        }
    }

    func testVersionOrderIsNumberNotText() {
        XCTAssertTrue(BundleFile.isOlder("1.2.0", than: "1.10.0"))
        XCTAssertTrue(BundleFile.isOlder("0.9.9", than: "1.0.0"))
        XCTAssertFalse(BundleFile.isOlder("1.0.0", than: "1.0.0"))
        XCTAssertFalse(BundleFile.isOlder("2.0.0", than: "1.99.99"))
    }
}
