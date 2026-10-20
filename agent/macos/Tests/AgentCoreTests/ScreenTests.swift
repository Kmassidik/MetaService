import XCTest
@testable import AgentCore
import MSCore

final class ScreenTests: XCTestCase {
    private func request(_ json: String) throws -> ScreenInputRequest { try ScreenInputRequest(body: Data(json.utf8)) }

    func testEventsAreReadStrictly() throws {
        let value = try request(#"{"events":[{"type":"move","x":5000,"y":10000},{"type":"button","button":"left","down":true},{"type":"scroll","dx":0,"dy":-3},{"type":"key","code":36,"down":true}]}"#)
        XCTAssertEqual(value.events, [.move(x: 5000, y: 10000), .button(.left, down: true), .scroll(dx: 0, dy: -3), .key(code: 36, down: true)])
    }

    func testBadInputIsRefused() {
        let bad = [#"{"events":[{"type":"move","x":10001,"y":0}]}"#, #"{"events":[{"type":"move","x":-1,"y":0}]}"#,
                   #"{"events":[{"type":"key","code":128,"down":true}]}"#, #"{"events":[{"type":"scroll","dx":51,"dy":0}]}"#,
                   #"{"events":[{"type":"button","button":"back","down":true}]}"#, #"{"events":[{"type":"nope"}]}"#,
                   #"{"events":[{"type":"move","x":1,"y":1,"extra":1}]}"#, #"{"other":1}"#, "not json"]
        for body in bad { XCTAssertThrowsError(try request(body), body) }
    }

    func testTooManyEventsAreRefused() {
        let one = #"{"type":"move","x":1,"y":1}"#
        let many = (0..<(ScreenInputRequest.maxEvents + 1)).map { _ in one }.joined(separator: ",")
        XCTAssertThrowsError(try request("{\"events\":[\(many)]}"))
        XCTAssertNoThrow(try request("{\"events\":[\((0..<ScreenInputRequest.maxEvents).map { _ in one }.joined(separator: ","))]}"))
    }

    func testTheSimulatedFrameIsAValidPngAndFollowsThePointer() async throws {
        let screen = SimulatedScreen()
        let first = try await screen.frame()
        XCTAssertEqual(first.contentType, "image/png")
        XCTAssertEqual(Array(first.data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(Array(first.data.suffix(12)).prefix(4), [0, 0, 0, 0])
        try await screen.send([.move(x: 5000, y: 5000)])
        let second = try await screen.frame()
        XCTAssertNotEqual(first.data, second.data, "moving the pointer changes the picture")
        try await screen.send([.button(.left, down: true)])
        let third = try await screen.frame()
        XCTAssertNotEqual(second.data, third.data, "pressing changes the marker colour")
        let status = await screen.status()
        XCTAssertEqual(status.access, .ready)
        XCTAssertEqual([status.width, status.height], [160, 100])
    }

    func testAScreenWithoutPermissionGivesNothingAndSaysWhy() async {
        let screen = SimulatedScreen(access: .needsPermission)
        let status = await screen.status()
        XCTAssertEqual(status.access, .needsPermission)
        XCTAssertNotNil(status.message)
        do { _ = try await screen.frame(); XCTFail("a frame without permission") } catch { XCTAssertEqual(error as? ScreenError, .notAllowed("The permission is missing on this computer.")) }
        do { try await screen.send([.move(x: 1, y: 1)]); XCTFail("input without permission") } catch {}
    }

    func testWhenItIsOffNothingWorks() async {
        let screen = ScreenOff()
        let status = await screen.status()
        XCTAssertEqual(status.access, .off)
        do { _ = try await screen.frame(); XCTFail() } catch {}
    }
}
