import XCTest
@testable import RootCore

final class McpJsonRpcTests: XCTestCase {
    private func parse(_ text: String) -> McpRpcMessage { McpJsonRpc.parse(Data(text.utf8)) }

    private func invalid(_ text: String) -> (id: McpRpcId, code: Int, message: String)? {
        guard case .invalid(let id, let code, let message) = parse(text) else { return nil }
        return (id, code, message)
    }

    func testARequestKeepsItsIdMethodAndParams() throws {
        guard case .request(let call) = parse(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_vms"}}"#) else { return XCTFail("not a request") }
        XCTAssertEqual(call.id, .number(7))
        XCTAssertEqual(call.method, "tools/call")
        let params = try XCTUnwrap(try JSONSerialization.jsonObject(with: call.params) as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "list_vms")
    }

    func testATextIdIsKept() {
        guard case .request(let call) = parse(#"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#) else { return XCTFail("not a request") }
        XCTAssertEqual(call.id, .text("abc"))
        XCTAssertEqual(call.params, Data("{}".utf8))
    }

    func testAMessageWithoutIdIsANotification() {
        XCTAssertEqual(parse(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#), .notification(method: "notifications/initialized"))
    }

    func testBrokenJsonIsMinus32700() {
        XCTAssertEqual(invalid("{nope")?.code, -32700)
        XCTAssertEqual(invalid("")?.code, -32700)
    }

    func testABatchIsRefusedAsAnInvalidRequest() {
        let refused = invalid(#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#)
        XCTAssertEqual(refused?.code, -32600)
        XCTAssertTrue(refused?.message.contains("batches") == true)
    }

    func testNotAnObjectOrWrongVersionOrNoMethodIsMinus32600() {
        for text in [#""text""#, "5", "null", #"{"id":1,"method":"ping"}"#, #"{"jsonrpc":"1.0","id":1,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":1}"#,
                     #"{"jsonrpc":"2.0","id":1,"method":5}"#, #"{"jsonrpc":"2.0","id":1,"method":""}"#] {
            XCTAssertEqual(invalid(text)?.code, -32600, text)
        }
    }

    func testABadIdIsMinus32600AndANonObjectParamsIsMinus32602() {
        for text in [#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":1.5,"method":"ping"}"#, #"{"jsonrpc":"2.0","id":[1],"method":"ping"}"#] {
            XCTAssertEqual(invalid(text)?.code, -32600, text)
        }
        XCTAssertEqual(invalid(#"{"jsonrpc":"2.0","id":3,"method":"ping","params":[1]}"#)?.code, -32602)
        XCTAssertEqual(invalid(#"{"jsonrpc":"2.0","id":3,"method":"ping","params":"x"}"#)?.id, .number(3))
    }

    func testRepliesCarryTheIdAndOneOfResultOrError() throws {
        let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: McpJsonRpc.result(id: .number(4), ["ok": true])) as? [String: Any])
        XCTAssertEqual(result["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(result["id"] as? Int, 4)
        XCTAssertNotNil(result["result"])
        XCTAssertNil(result["error"])
        let failure = try XCTUnwrap(try JSONSerialization.jsonObject(with: McpJsonRpc.error(id: .none, code: -32601, message: "no")) as? [String: Any])
        XCTAssertTrue(failure["id"] is NSNull)
        XCTAssertEqual((failure["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertNil(failure["result"])
    }
}

final class McpProtocolTests: XCTestCase {
    func testAKnownVersionIsAnsweredAsAskedAndAnythingElseGetsTheNewest() {
        for version in ["2025-06-18", "2025-03-26", "2024-11-05"] { XCTAssertEqual(McpProtocol.negotiate(requested: version), version) }
        XCTAssertEqual(McpProtocol.negotiate(requested: "2023-01-01"), "2025-06-18")
        XCTAssertEqual(McpProtocol.negotiate(requested: nil), "2025-06-18")
        XCTAssertEqual(McpProtocol.negotiate(requested: ""), "2025-06-18")
    }

    func testStructuredContentFrom20250618() {
        XCTAssertTrue(McpProtocol.supportsStructuredContent(version: "2025-06-18"))
        XCTAssertFalse(McpProtocol.supportsStructuredContent(version: "2025-03-26"))
        XCTAssertFalse(McpProtocol.supportsStructuredContent(version: "2024-11-05"))
    }

    func testOriginRules() {
        let own = "https://meta.ruvio.site"
        XCTAssertTrue(McpProtocol.originAllowed(nil, publicURL: own))
        XCTAssertTrue(McpProtocol.originAllowed("https://meta.ruvio.site", publicURL: own))
        XCTAssertTrue(McpProtocol.originAllowed("https://META.ruvio.site", publicURL: own))
        XCTAssertFalse(McpProtocol.originAllowed("https://evil.example", publicURL: own))
        XCTAssertFalse(McpProtocol.originAllowed("https://meta.ruvio.site.evil.example", publicURL: own))
        XCTAssertFalse(McpProtocol.originAllowed("null", publicURL: own))
        XCTAssertFalse(McpProtocol.originAllowed("", publicURL: own))
        XCTAssertFalse(McpProtocol.originAllowed("https://meta.ruvio.site:8443", publicURL: own))
        XCTAssertTrue(McpProtocol.originAllowed("http://localhost:9100", publicURL: "http://localhost:9100"))
    }

    func testAToolResultHasTextAndStructuredContentByVersion() throws {
        let newer = McpProtocol.toolResult(["a": 1], isError: false, version: "2025-06-18")
        XCTAssertEqual(newer["isError"] as? Bool, false)
        XCTAssertNotNil(newer["structuredContent"])
        let text = ((newer["content"] as? [[String: Any]])?.first?["text"]) as? String
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data((text ?? "").utf8)) as? [String: Int], ["a": 1])
        let older = McpProtocol.toolResult(["a": 1], isError: false, version: "2025-03-26")
        XCTAssertNil(older["structuredContent"])
        XCTAssertNotNil(older["content"])
    }

    func testAFailureIsMarkedAndKeepsTheSentence() {
        let result = McpProtocol.failureResult("do this next", version: "2025-06-18")
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertEqual((result["structuredContent"] as? [String: String])?["error"], "do this next")
    }
}
