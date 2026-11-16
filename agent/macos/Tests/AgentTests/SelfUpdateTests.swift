import CryptoKit
import XCTest
@testable import Agent

final class SelfUpdateTests: XCTestCase {
    func testABuildIsLowercaseHexOfASensibleLength() {
        XCTAssertTrue(SelfUpdate.validBuild("3bf6cd0c"))
        XCTAssertFalse(SelfUpdate.validBuild("3BF6CD0C"))
        XCTAssertFalse(SelfUpdate.validBuild("abc"))
        XCTAssertFalse(SelfUpdate.validBuild(String(repeating: "a", count: 65)))
    }

    func testOnlyTheAskedForMacProgramIsAccepted() {
        var program = Data(SelfUpdate.machOMagic)
        program.append(Data("the rest of the program".utf8))
        let build = SHA256.hash(data: program).map { String(format: "%02x", $0) }.joined()
        XCTAssertNil(SelfUpdate.verified(program, wanted: String(build.prefix(8))))
        XCTAssertTrue(SelfUpdate.verified(program, wanted: "deadbeef")?.contains("not the build") ?? false)
        XCTAssertTrue(SelfUpdate.verified(Data("MZ".utf8), wanted: "deadbeef")?.contains("not a Mac program") ?? false)
    }

    func testALabelWithOddCharactersIsRefused() {
        XCTAssertTrue(SelfUpdate.validLabel("io.metaservice.join"))
        XCTAssertFalse(SelfUpdate.validLabel("bad label;rm"))
        XCTAssertFalse(SelfUpdate.validLabel(""))
    }

    func testAComputerThatNeverJoinedThroughTheScriptIsLeftAlone() async {
        let dir = NSTemporaryDirectory() + "ms-selfup-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir + "/.metaservice-join/state", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let update = SelfUpdate(stateDirectory: dir + "/.metaservice-join/state", root: nil, machineToken: nil, ownPath: "/nonexistent", currentBuild: nil)
        let outcome = await update.run(wanted: "deadbeef")
        XCTAssertEqual(outcome, .notJoined)
    }

    func testAHelperThatAlreadyIsThatBuildDoesNothing() async throws {
        let dir = NSTemporaryDirectory() + "ms-selfup-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir + "/.metaservice-join/state", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data("MS_LABEL=io.metaservice.join\nMS_UNIT=/tmp/x.plist\nMS_UID=501\n".utf8).write(to: URL(fileURLWithPath: dir + "/.metaservice-join/joined.env"))
        let update = SelfUpdate(stateDirectory: dir + "/.metaservice-join/state", root: nil, machineToken: nil, ownPath: "/nonexistent", currentBuild: "deadbeefcafe")
        let outcome = await update.run(wanted: "deadbeef")
        XCTAssertEqual(outcome, .current)
    }

    func testTheQuotedEnvFileTheJoinScriptWritesIsAccepted() async throws {
        // Regression 2026-11-16: join.sh writes every value shell-quoted for leave.sh to source, so the
        // reader saw 'io.metaservice.join' with literal quotes, refused the label and answered not_joined.
        // This is the real file content a Mac join writes today.
        let dir = NSTemporaryDirectory() + "ms-selfup-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir + "/.metaservice-join/state", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try Data("MS_OS='mac'\nMS_LABEL='io.metaservice.join'\nMS_UNIT='/tmp/x.plist'\nMS_UID='501'\n".utf8).write(to: URL(fileURLWithPath: dir + "/.metaservice-join/joined.env"))
        let update = SelfUpdate(stateDirectory: dir + "/.metaservice-join/state", root: nil, machineToken: nil, ownPath: "/nonexistent", currentBuild: "deadbeefcafe")
        let outcome = await update.run(wanted: "deadbeef")
        XCTAssertEqual(outcome, .current)
    }
}
