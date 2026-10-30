import XCTest
@testable import RootCore

final class JoinShareRulesTests: XCTestCase {
    private func hub(_ method: String, _ path: String) -> JoinShareCall? {
        guard case .hub(let call)? = JoinShareRules.match(method: method, path: path) else { return nil }
        return call
    }

    // MARK: the allow-list

    func testEveryAllowedRouteMapsToItsHubRoute() {
        XCTAssertEqual(JoinShareRules.match(method: "GET", path: "/api/join-share/status"), .status)
        XCTAssertEqual(hub("GET", "/api/join-share/supported")?.hubPath, "/admin/supported")
        XCTAssertEqual(hub("GET", "/api/join-share/pending")?.hubPath, "/admin/pending")
        XCTAssertEqual(hub("GET", "/api/join-share/peers")?.hubPath, "/admin/peers")
        XCTAssertEqual(hub("POST", "/api/join-share/links")?.hubPath, "/admin/links")
        XCTAssertEqual(hub("POST", "/api/join-share/pending/abc-1/approve")?.hubPath, "/admin/pending/abc-1/approve")
        XCTAssertEqual(hub("POST", "/api/join-share/pending/abc-1/refuse")?.hubPath, "/admin/pending/abc-1/refuse")
        XCTAssertEqual(hub("DELETE", "/api/join-share/peers/my-mac.local")?.hubPath, "/admin/peers/my-mac.local")
    }

    func testOnlyTheFourWritesAreAuditedWithTheirTarget() {
        XCTAssertEqual(hub("POST", "/api/join-share/links")?.auditAction, "join_share.link")
        XCTAssertEqual(hub("POST", "/api/join-share/pending/p1/approve")?.auditAction, "join_share.approve")
        XCTAssertEqual(hub("POST", "/api/join-share/pending/p1/approve")?.auditTarget, "p1")
        XCTAssertEqual(hub("POST", "/api/join-share/pending/p1/refuse")?.auditAction, "join_share.refuse")
        XCTAssertEqual(hub("DELETE", "/api/join-share/peers/box")?.auditAction, "join_share.remove")
        XCTAssertEqual(hub("DELETE", "/api/join-share/peers/box")?.auditTarget, "box")
        XCTAssertNil(hub("GET", "/api/join-share/pending")?.auditAction)
    }

    func testAnotherMethodOrPathIsNoMatch() {
        let refused: [(String, String)] = [
            ("POST", "/api/join-share/status"), ("DELETE", "/api/join-share/status"), ("PUT", "/api/join-share/links"),
            ("GET", "/api/join-share/links"), ("GET", "/api/join-share/pending/p1/approve"), ("DELETE", "/api/join-share/pending/p1"),
            ("GET", "/api/join-share/peers/box"), ("POST", "/api/join-share/peers"), ("POST", "/api/join-share/pending/p1/delete"),
            ("GET", "/api/join-share"), ("GET", "/api/join-share/"), ("GET", "/api/join-share/peers/"), ("GET", "/api/join-share/admin/peers"),
            ("GET", "/api/join-share/pending/"), ("GET", "/api/other"), ("GET", "/api/join-sharex/peers"), ("get", "/api/join-share/peers"),
        ]
        for (method, path) in refused { XCTAssertNil(JoinShareRules.match(method: method, path: path), "\(method) \(path)") }
    }

    func testAnInvalidIdOrNameIsNoMatchSoItNeverReachesAPath() {
        let bad = ["..", ".", "a b", "a%2Fb", "a:b", "a\\b", "é", String(repeating: "a", count: 65), "a;b", "a?x=1"]
        for text in bad {
            XCTAssertNil(JoinShareRules.match(method: "DELETE", path: "/api/join-share/peers/\(text)"), text)
            XCTAssertNil(JoinShareRules.match(method: "POST", path: "/api/join-share/pending/\(text)/approve"), text)
        }
        XCTAssertNil(JoinShareRules.match(method: "DELETE", path: "/api/join-share/peers/a/b"))
        XCTAssertNil(JoinShareRules.match(method: "DELETE", path: "/api/join-share/peers/../links"))
    }

    // MARK: names

    func testNameRules() {
        for good in ["a", "My_Mac-1.local", String(repeating: "z", count: 64), "0", "..a", "a.."] { XCTAssertTrue(JoinShareRules.isValidName(good), good) }
        for bad in ["", ".", "..", String(repeating: "z", count: 65), "a/b", "a b", "a\n", "ü"] { XCTAssertFalse(JoinShareRules.isValidName(bad), bad) }
    }

    // MARK: bodies

    func testOnlyOneJsonObjectOrNothingIsForwarded() {
        XCTAssertTrue(JoinShareRules.isForwardableBody(Data()))
        XCTAssertTrue(JoinShareRules.isForwardableBody(Data(#"{"code":"123456","name":"box"}"#.utf8)))
        for bad in ["[1]", "\"x\"", "42", "not json", "{"] { XCTAssertFalse(JoinShareRules.isForwardableBody(Data(bad.utf8)), bad) }
    }

    func testABodyOverSixteenKiBIsNotForwarded() {
        let big = Data(#"{"x":""#.utf8) + Data(repeating: 97, count: JoinShareRules.maxBodyBytes) + Data(#""}"#.utf8)
        XCTAssertFalse(JoinShareRules.isForwardableBody(big))
    }

    func testTheLinkAuditTargetIsOsAndCpuOnly() {
        XCTAssertEqual(JoinShareRules.linkTarget(body: Data(#"{"os":"mac","cpu":"arm64","extra":"secret"}"#.utf8)), "mac/arm64")
        for bad in ["", "{}", #"{"os":"mac"}"#, #"{"os":"../x","cpu":"a"}"#, #"{"os":1,"cpu":2}"#, "nope"] {
            XCTAssertEqual(JoinShareRules.linkTarget(body: Data(bad.utf8)), "link", bad)
        }
    }

    // MARK: settings

    func testTheAdminAddress() {
        for good in ["http://127.0.0.1:9111", "http://localhost:9111/", "https://hub.example.com", "https://hub.example.com:9111"] {
            XCTAssertTrue(JoinShareRules.isAcceptableAdminURL(good), good)
        }
        for bad in ["", "nonsense", "ftp://127.0.0.1", "http://hub.example.com", "http://10.0.0.5:9111", "https://u:p@hub.example.com",
                    "https://hub.example.com/admin", "https://hub.example.com?x=1", "https://hub.example.com#k", "file:///etc/passwd"] {
            XCTAssertFalse(JoinShareRules.isAcceptableAdminURL(bad), bad)
        }
    }

    func testTheKeyFileTextIsTrimmedAndEmptyMeansNoKey() {
        XCTAssertEqual(JoinShareRules.adminKey(fileText: "abc123\n"), "abc123")
        XCTAssertNil(JoinShareRules.adminKey(fileText: " \n"))
        XCTAssertNil(JoinShareRules.adminKey(fileText: ""))
    }

    // MARK: hub replies

    func testAReplyIsPassedOnOnlyWhenItIsJsonAndHoldsNoKey() {
        XCTAssertTrue(JoinShareRules.isPassableReply(Data(#"{"error":"wrong_code","tries_left":2}"#.utf8), key: "k3y"))
        XCTAssertTrue(JoinShareRules.isPassableReply(Data(), key: "k3y"))
        XCTAssertFalse(JoinShareRules.isPassableReply(Data("<html>".utf8), key: "k3y"))
        XCTAssertFalse(JoinShareRules.isPassableReply(Data(#"{"echo":"k3y"}"#.utf8), key: "k3y"))
        XCTAssertFalse(JoinShareRules.isPassableReply(Data(repeating: 32, count: JoinShareRules.maxReplyBytes + 1), key: "k3y"))
    }
}
