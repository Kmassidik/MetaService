import XCTest
@testable import RootCore

final class StorageReplyTests: XCTestCase {
    private let storage = Storage(scanning: false, progress: nil, error: nil, map: nil)

    private func text(_ reply: StorageReply) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: try encoder.encode(reply), as: UTF8.self)
    }

    func testAGoodAnswerIsOnlineWithTheHelpersStorage() {
        let reply = StorageReply.make(.fresh(storage))
        XCTAssertEqual(reply.state, "online")
        XCTAssertEqual(reply.storage, storage)
    }

    func testAnOldHelperIsNamedAndHasNoStorage() throws {
        let reply = StorageReply.make(.oldHelper)
        XCTAssertEqual(reply.state, "old_helper")
        XCTAssertNil(reply.storage)
        XCTAssertEqual(try text(reply), "{\"state\":\"old_helper\",\"storage\":null}")
    }

    func testAnOfflineOrSilentMachineIsOfflineWithStorageWrittenAsNull() throws {
        let reply = StorageReply.make(.unreachable)
        XCTAssertEqual(reply.state, "offline")
        XCTAssertEqual(try text(reply), "{\"state\":\"offline\",\"storage\":null}")
    }

    func testTheHelpersAnswerIsWrittenWithEveryKey() throws {
        let written = try text(.make(.fresh(storage)))
        XCTAssertTrue(written.contains("\"state\":\"online\""), written)
        XCTAssertTrue(written.contains("\"scanning\":false"), written)
        XCTAssertTrue(written.contains("\"progress\":null"), written)
        XCTAssertTrue(written.contains("\"error\":null"), written)
        XCTAssertTrue(written.contains("\"map\":null"), written)
    }
}
