import XCTest
@testable import Agent

final class LeaveRoutesTests: XCTestCase {
    private var dir = ""

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "ms-leave-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir + "/.metaservice-join/state", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    private func joinedEnv() throws {
        let home = dir + "/.metaservice-join"
        try Data("x".utf8).write(to: URL(fileURLWithPath: dir + "/unit.plist"))
        let env = "MS_NAME=mac\nMS_OS=mac\nMS_BOOT=mac-launchd\nMS_UID=501\nMS_IFACE=metaservice\nMS_CONF=\(dir)/wg.conf\nMS_HOME=\(home)\nMS_UNIT=\(dir)/unit.plist\nMS_LABEL=io.metaservice.join\nMS_WG_PLIST=\(dir)/wg.plist\n"
        try Data(env.utf8).write(to: URL(fileURLWithPath: home + "/joined.env"))
    }

    private func fakeSudo() throws -> String {
        let path = dir + "/fake-sudo"
        try Data("#!/bin/sh\nread -r pw\n[ \"$pw\" = secret ] || exit 1\nexit 0\n".utf8).write(to: URL(fileURLWithPath: path))
        chmod(path, 0o755)
        return path
    }

    func testTheCopyInTheHelperIsTheScriptInTheJoinFolder() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("agent/linux/src/leave-from-panel.sh")
        let original = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(LeaveScript.text + "\n", original, "regenerate LeaveScript.swift from agent/linux/src/leave-from-panel.sh")
    }

    func testAWrongPasswordChangesNothing() async throws {
        try joinedEnv()
        let outcome = await LeaveRoutes.run(stateDirectory: dir + "/.metaservice-join/state", password: "nope", sudo: try fakeSudo())
        guard case .failed(let why) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(why.contains("sudo did not accept"))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir + "/.metaservice-join/joined.env"))
    }

    func testTheRightPasswordCleansUpAfterTheRootStep() async throws {
        try joinedEnv()
        let outcome = await LeaveRoutes.run(stateDirectory: dir + "/.metaservice-join/state", password: "secret", sudo: try fakeSudo())
        XCTAssertEqual(outcome, .leaving)
        try await Task.sleep(nanoseconds: 3_500_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/.metaservice-join"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/unit.plist"))
    }

    func testAComputerThatNeverJoinedThroughTheScriptIsNotTouched() async {
        let outcome = await LeaveRoutes.run(stateDirectory: dir + "/.metaservice-join/state", password: "secret", sudo: nil)
        XCTAssertEqual(outcome, .notJoined)
    }

    func testMarkersAreReadAndOtherLinesIgnored() {
        XCTAssertEqual(LeaveRoutes.read(marker: "ms-leave: root-ok"), .leaving)
        XCTAssertEqual(LeaveRoutes.read(marker: "ms-leave: root-failed: sudo needs a password"), .failed("sudo needs a password"))
        XCTAssertNil(LeaveRoutes.read(marker: "hello"))
    }
}
