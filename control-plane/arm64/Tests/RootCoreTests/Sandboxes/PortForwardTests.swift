import Foundation
import XCTest
@testable import RootCore

/// The way a port request is rewritten for the helper: the path passes through, and our own token is taken out of the query.
final class PortForwardTests: XCTestCase {
    private let sandbox = "abcdefghij0123456789"

    func testThePathIsTheHelpersPortRoute() {
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "/index.html", query: nil),
                       "/v1/sandboxes/\(sandbox)/ports/8080/index.html")
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "/", query: nil),
                       "/v1/sandboxes/\(sandbox)/ports/8080/")
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "", query: nil),
                       "/v1/sandboxes/\(sandbox)/ports/8080/")
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 49983, path: "/files/a%20b.txt", query: nil),
                       "/v1/sandboxes/\(sandbox)/ports/49983/files/a%20b.txt")
    }

    func testTheQueryKeepsEverythingButOurToken() {
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "/x", query: "a=1&token=secret&b=2"),
                       "/v1/sandboxes/\(sandbox)/ports/8080/x?a=1&b=2")
        XCTAssertEqual(PortForward.queryWithoutToken("a=1&token=secret&b=2"), "a=1&b=2")
        XCTAssertEqual(PortForward.queryWithoutToken("token=secret"), nil)
        XCTAssertEqual(PortForward.queryWithoutToken("token"), nil)
        XCTAssertEqual(PortForward.queryWithoutToken("tokens=1&mytoken=2"), "tokens=1&mytoken=2")
        XCTAssertEqual(PortForward.queryWithoutToken(nil), nil)
        XCTAssertEqual(PortForward.queryWithoutToken(""), nil)
    }

    func testTheQueryOrderAndEncodingAreKept() {
        XCTAssertEqual(PortForward.queryWithoutToken("q=a%20b&x=%2F&token=t"), "q=a%20b&x=%2F")
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "/s", query: "q=a%20b"), "/v1/sandboxes/\(sandbox)/ports/8080/s?q=a%20b")
    }

    func testATokenOnlyQueryLeavesNoQuestionMark() {
        XCTAssertEqual(PortForward.path(sandbox: sandbox, port: 8080, path: "/s", query: "token=t"),
                       "/v1/sandboxes/\(sandbox)/ports/8080/s")
    }
}
