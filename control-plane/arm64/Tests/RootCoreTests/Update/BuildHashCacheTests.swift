import XCTest
@testable import RootCore

final class BuildHashCacheTests: XCTestCase {
    private var folder: String!

    override func setUpWithError() throws {
        folder = NSTemporaryDirectory() + "ms-hash-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: folder) }

    private func write(_ text: String, as name: String = "program") throws -> String {
        let path = folder + "/" + name
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testTheBuildIsTheSha256OfTheFileInLowercaseHex() throws {
        // echo -n "abc" | shasum -a 256
        let path = try write("abc")
        XCTAssertEqual(BuildHashCache().build(ofFileAt: path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testABigFileIsHashedInPiecesAndGivesTheSameAnswer() throws {
        let text = String(repeating: "metaservice", count: 300_000)
        let path = try write(text)
        let expected = BuildHashCache.sha256(of: Data(text.utf8))
        XCTAssertEqual(BuildHashCache().build(ofFileAt: path), expected)
    }

    func testAMissingOrUnreadableFileHasNoBuild() throws {
        XCTAssertNil(BuildHashCache().build(ofFileAt: folder + "/nothing"))
        XCTAssertNil(BuildHashCache().build(ofFileAt: folder), "a folder is not a program")
    }

    func testTheAnswerIsKeptWhileThePathSizeAndTimeStayTheSame() throws {
        let cache = BuildHashCache()
        let path = try write("first")
        let first = cache.build(ofFileAt: path)
        XCTAssertEqual(cache.hashesComputed, 1)
        XCTAssertEqual(cache.build(ofFileAt: path), first)
        XCTAssertEqual(cache.hashesComputed, 1, "the file is not read again")
    }

    func testAChangedFileIsHashedAgain() throws {
        let cache = BuildHashCache()
        let path = try write("first")
        let first = cache.build(ofFileAt: path)
        try Data("second, longer".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertNotEqual(cache.build(ofFileAt: path), first)
        XCTAssertEqual(cache.hashesComputed, 2)
    }

    func testSameSizeButANewerTimeIsHashedAgain() throws {
        let cache = BuildHashCache()
        let path = try write("aaaa")
        let first = cache.build(ofFileAt: path)
        try Data("bbbb".utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: path)
        XCTAssertNotEqual(cache.build(ofFileAt: path), first)
        XCTAssertEqual(cache.hashesComputed, 2)
    }
}
