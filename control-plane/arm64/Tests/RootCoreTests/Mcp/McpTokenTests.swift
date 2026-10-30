import XCTest
@testable import RootCore

final class McpTokenTests: XCTestCase {
    func testANewTokenIsMskAnd43UrlSafeCharacters() {
        let token = McpToken.make()
        XCTAssertTrue(token.hasPrefix("msk_"))
        XCTAssertEqual(token.count, 4 + 43)
        XCTAssertTrue(McpToken.isWellFormed(token))
        XCTAssertTrue(token.dropFirst(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    func testTokensDoNotRepeat() {
        XCTAssertEqual(Set((0..<200).map { _ in McpToken.make() }).count, 200)
    }

    func testOnlyTheExactShapeIsWellFormed() {
        let secret = String(repeating: "a", count: 43)
        XCTAssertTrue(McpToken.isWellFormed("msk_" + secret))
        let bad = ["", "msk_", "msk_" + String(repeating: "a", count: 42), "msk_" + String(repeating: "a", count: 44), "msx_" + secret,
                   "msk_" + String(repeating: "a", count: 42) + "+", "msk_" + String(repeating: "a", count: 42) + "=", "msk_" + String(repeating: "a", count: 42) + " ",
                   "MSK_" + secret, secret, " msk_" + secret, "msk_" + String(repeating: "é", count: 43)]
        for text in bad { XCTAssertFalse(McpToken.isWellFormed(text), text) }
    }

    func testTheHashIs64HexAndHidesTheToken() {
        let token = "msk_" + String(repeating: "b", count: 43)
        let hash = McpToken.hash(token)
        XCTAssertEqual(hash.count, 64)
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertFalse(hash.contains("bbbbbbbb"))
        XCTAssertEqual(hash, McpToken.hash(token))
        XCTAssertNotEqual(hash, McpToken.hash("msk_" + String(repeating: "c", count: 43)))
    }

    func testThePrefixIsTheFirst8CharactersAfterTheMarker() {
        XCTAssertEqual(McpToken.displayPrefix(of: "msk_ABCDEFGHijklmnop"), "ABCDEFGH")
        XCTAssertEqual(McpToken.displayPrefix(of: McpToken.make()).count, 8)
    }
}

final class McpScopeTests: XCTestCase {
    func testTheDefaultIsReadAndCreate() {
        XCTAssertEqual(McpScope.defaults, [.read, .create])
    }

    func testParseAcceptsEveryScopeAndKeepsAFixedOrder() throws {
        let all = try McpScope.parse(["shared", "gpu", "destroy", "create", "read"])
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(McpScope.names(all), ["read", "create", "destroy", "gpu", "shared"])
    }

    func testParseRefusesEmptyUnknownAndRepeated() {
        XCTAssertThrowsError(try McpScope.parse([]))
        XCTAssertThrowsError(try McpScope.parse(["read", "root"]))
        XCTAssertThrowsError(try McpScope.parse(["read", "read"]))
        XCTAssertThrowsError(try McpScope.parse(["READ"]))
    }

    func testTheRefusalNamesTheAllowedScopes() {
        XCTAssertThrowsError(try McpScope.parse(["nope"])) { error in
            XCTAssertTrue((error as? InputError)?.message.contains("read, create, destroy, gpu, shared") == true)
        }
    }
}

final class McpToolCatalogTests: XCTestCase {
    func testNineToolsWithTheScopesOfTheSpec() {
        XCTAssertEqual(McpTool.allCases.count, 9)
        let scopes: [String: McpScope] = ["list_machines": .read, "machine_capacity": .read, "list_vms": .read, "vm_status": .read, "get_request": .read,
                                          "create_vm": .create, "start_vm": .create, "stop_vm": .create, "delete_vm": .destroy]
        for tool in McpTool.allCases { XCTAssertEqual(scopes[tool.rawValue], tool.scope, tool.rawValue) }
    }

    func testEveryToolHasOneSentenceDescription() {
        for tool in McpTool.allCases {
            XCTAssertFalse(tool.description.isEmpty)
            XCTAssertTrue(tool.description.hasSuffix("."), tool.rawValue)
            XCTAssertLessThan(tool.description.count, 260, tool.rawValue)
        }
    }
}
