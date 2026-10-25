import XCTest
@testable import RootCore

final class StorageTests: XCTestCase {
    private func node(parent: Int, name: String = "home", type: String = "dir", bytes: Int = 600, kind: String = "code", reclaim: String = "null") -> String {
        "{\"parent\":\(parent),\"name\":\"\(name)\",\"type\":\"\(type)\",\"bytes\":\(bytes),\"files\":3,\"items\":2,\"kind\":\"\(kind)\",\"reclaim\":\(reclaim),\"modified\":1761400000}"
    }

    /// A small good tree: the scanned folder, a folder in it, a file in that folder, and the rest of the top folder.
    private var tree: [String] {
        [node(parent: -1, name: "/"), node(parent: 0, name: "home"), node(parent: 1, name: "big.iso", type: "file", bytes: 400, kind: "media", reclaim: "\"trash\""),
         node(parent: 0, name: "", type: "rest", bytes: 50, kind: "other")]
    }

    private func answer(nodes: [String]? = nil, error: String = "null", progress: String = "null", extra: String = "") -> Data {
        let list = (nodes ?? tree).joined(separator: ",")
        return Data("""
        {"scanning":false,"progress":\(progress),"error":\(error),
         "map":{"root":"/","finished_at":"2026-10-25T10:00:00Z","seconds":12.5,"entries":5000,"unreadable":2,
                "disk":{"total_bytes":1000,"used_bytes":600,"free_bytes":400},"nodes":[\(list)]}\(extra)}
        """.utf8)
    }

    private func encoded(_ storage: Storage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(storage)
    }

    func testAGoodAnswerIsReadAsItIsAndComesBackTheSame() throws {
        let storage = try Storage.parse(answer())
        XCTAssertEqual(storage.map?.nodes.count, 4)
        XCTAssertEqual(storage.map?.nodes[2].name, "big.iso")
        XCTAssertEqual(storage.map?.nodes[2].reclaim, "trash")
        XCTAssertEqual(storage.map?.disk.usedBytes, 600)
        XCTAssertEqual(storage.map?.finishedAt, "2026-10-25T10:00:00Z")
        XCTAssertEqual(try Storage.parse(try encoded(storage)), storage)
    }

    func testItEncodesWithSnakeCaseKeysAndEveryKeyAlwaysThere() throws {
        let text = String(decoding: try encoded(try Storage.parse(answer())), as: UTF8.self)
        XCTAssertTrue(text.contains("\"finished_at\""), text)
        XCTAssertTrue(text.contains("\"used_bytes\":600"), text)
        XCTAssertTrue(text.contains("\"progress\":null"), text)
        XCTAssertTrue(text.contains("\"error\":null"), text)
        XCTAssertTrue(text.contains("\"reclaim\":null"), text)
        XCTAssertTrue(text.contains("\"type\":\"rest\""), text)
    }

    func testNoMapYetIsAccepted() throws {
        let storage = try Storage.parse(Data("{\"scanning\":true,\"progress\":{\"entries\":10,\"bytes\":20},\"error\":null,\"map\":null}".utf8))
        XCTAssertTrue(storage.scanning)
        XCTAssertEqual(storage.progress, .init(entries: 10, bytes: 20))
        XCTAssertNil(storage.map)
        XCTAssertTrue(String(decoding: try encoded(storage), as: UTF8.self).contains("\"map\":null"))
    }

    func testAnAnswerBiggerThanTheLimitIsRefused() {
        let padded = answer(extra: ",\"junk\":\"" + String(repeating: "x", count: Storage.maxAnswerBytes) + "\"")
        XCTAssertThrowsError(try Storage.parse(padded)) { XCTAssertEqual($0 as? StorageError, .tooBig) }
    }

    func testAnAnswerMissingARequiredPartIsRefused() {
        XCTAssertThrowsError(try Storage.parse(Data("{\"progress\":null,\"error\":null,\"map\":null}".utf8))) { XCTAssertEqual($0 as? StorageError, .notAnAnswer) }
        XCTAssertThrowsError(try Storage.parse(Data("not json".utf8))) { XCTAssertEqual($0 as? StorageError, .notAnAnswer) }
    }

    func testAParentThatIsNotAnEarlierEntryIsRefused() {
        let later = [node(parent: -1), node(parent: 2), node(parent: 0)]
        let itself = [node(parent: -1), node(parent: 1)]
        let outside = [node(parent: -1), node(parent: 99)]
        let noParent = [node(parent: -1), node(parent: -1)]
        for nodes in [later, itself, outside, noParent] {
            XCTAssertThrowsError(try Storage.parse(answer(nodes: nodes))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
        }
    }

    func testTheFirstEntryMustHaveNoParent() {
        XCTAssertThrowsError(try Storage.parse(answer(nodes: [node(parent: 0)]))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
    }

    func testAParentThatIsAFileOrARestIsRefused() {
        let underFile = [node(parent: -1), node(parent: 0, type: "file"), node(parent: 1, name: "inside")]
        let underRest = [node(parent: -1), node(parent: 0, name: "", type: "rest"), node(parent: 1, name: "inside")]
        for nodes in [underFile, underRest] {
            XCTAssertThrowsError(try Storage.parse(answer(nodes: nodes))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
        }
    }

    func testAnUnknownTypeIsRefused() {
        XCTAssertThrowsError(try Storage.parse(answer(nodes: [node(parent: -1), node(parent: 0, type: "symlink")]))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
    }

    func testNoEntriesOrMoreThanTheLimitAreRefused() {
        XCTAssertThrowsError(try Storage.parse(answer(nodes: []))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
        let many = [node(parent: -1)] + Array(repeating: node(parent: 0, type: "file"), count: Storage.maxNodes)
        XCTAssertThrowsError(try Storage.parse(answer(nodes: many))) { XCTAssertEqual($0 as? StorageError, .brokenMap) }
    }

    func testExactlyTheLimitIsKept() throws {
        let full = [node(parent: -1)] + Array(repeating: node(parent: 0, type: "file"), count: Storage.maxNodes - 1)
        XCTAssertEqual(try Storage.parse(answer(nodes: full)).map?.nodes.count, 12_000)
    }

    func testAnUnknownKindIsReadAsOther() throws {
        let storage = try Storage.parse(answer(nodes: [node(parent: -1, kind: "holograms"), node(parent: 0, kind: "vms")]))
        XCTAssertEqual(storage.map?.nodes.map(\.kind), ["other", "vms"])
    }

    func testAnUnknownReasonIsDroppedAndAKnownOneKept() throws {
        let storage = try Storage.parse(answer(nodes: [node(parent: -1, reclaim: "\"delete_me_now\""), node(parent: 0, reclaim: "\"build_output\"")]))
        XCTAssertNil(storage.map?.nodes[0].reclaim)
        XCTAssertEqual(storage.map?.nodes[1].reclaim, "build_output")
    }

    func testLongNamesAndErrorsAreCut() throws {
        let storage = try Storage.parse(answer(nodes: [node(parent: -1, name: String(repeating: "é", count: 900))], error: "\"" + String(repeating: "e", count: 2000) + "\""))
        XCTAssertEqual(storage.map?.nodes[0].name.count, 255)
        XCTAssertEqual(storage.error?.count, 300)
    }

    func testHostileNamesAreKeptAsTextNotChanged() throws {
        let storage = try Storage.parse(answer(nodes: [node(parent: -1, name: "<img src=x onerror=alert(1)>")]))
        XCTAssertEqual(storage.map?.nodes[0].name, "<img src=x onerror=alert(1)>")
    }

    func testNegativeNumbersBecomeZero() throws {
        let data = Data("""
        {"scanning":true,"progress":{"entries":-5,"bytes":-1},"error":null,
         "map":{"root":"/","finished_at":"2026-10-25T10:00:00Z","seconds":-3.0,"entries":-1,"unreadable":-2,
                "disk":{"total_bytes":-1,"used_bytes":-1,"free_bytes":-1},
                "nodes":[{"parent":-1,"name":"/","type":"dir","bytes":-10,"files":-1,"items":-1,"kind":"other","reclaim":null,"modified":null}]}}
        """.utf8)
        let storage = try Storage.parse(data)
        XCTAssertEqual(storage.progress, .init(entries: 0, bytes: 0))
        let map = try XCTUnwrap(storage.map)
        XCTAssertEqual([map.entries, map.unreadable, map.disk.totalBytes, map.disk.usedBytes, map.disk.freeBytes], [0, 0, 0, 0, 0])
        XCTAssertEqual(map.seconds, 0)
        XCTAssertEqual([map.nodes[0].bytes, map.nodes[0].files, map.nodes[0].items], [0, 0, 0])
        XCTAssertNil(map.nodes[0].modified)
    }

    func testSecondsThatAreNotANumberBecomeZero() throws {
        var storage = try Storage.parse(answer())
        storage.map?.seconds = .infinity
        XCTAssertEqual(try storage.limited().map?.seconds, 0)
        storage.map?.seconds = .nan
        XCTAssertEqual(try storage.limited().map?.seconds, 0)
    }
}
