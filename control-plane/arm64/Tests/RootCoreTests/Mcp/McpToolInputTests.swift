import XCTest
@testable import RootCore

final class McpToolInputTests: XCTestCase {
    private func create(_ json: String) throws -> McpCreateVmInput { try McpCreateVmInput(arguments: Data(json.utf8)) }

    func testAPresetTakesItsNumbersAndTheDefaults() throws {
        let input = try create(#"{"size":"medium"}"#)
        XCTAssertEqual(input.dimensions, McpSize.medium.preset)
        XCTAssertEqual(input.waitSeconds, 30)
        XCTAssertNil(input.machine)
        XCTAssertNil(input.gpuMemoryGb)
    }

    func testEverythingGivenIsRead() throws {
        let input = try create(#"{"machine":"mini","name":"web-1","size":"small","image":"blank","gpu_memory_gb":4,"ssh_public_key":"ssh-ed25519 AAAA","idempotency_key":"job:1","wait_seconds":0}"#)
        XCTAssertEqual(input.machine, "mini")
        XCTAssertEqual(input.name, "web-1")
        XCTAssertEqual(input.gpuMemoryGb, 4)
        XCTAssertEqual(input.idempotencyKey, "job:1")
        XCTAssertEqual(input.waitSeconds, 0)
    }

    func testCustomNeedsAllThreeNumbersAndAPresetRefusesThem() throws {
        let custom = try create(#"{"size":"custom","vcpu":3,"ram_mb":1024,"disk_gb":10}"#)
        XCTAssertEqual(custom.dimensions, .init(vcpu: 3, ramMb: 1024, diskGb: 10))
        XCTAssertThrowsError(try create(#"{"size":"custom","vcpu":3}"#))
        XCTAssertThrowsError(try create(#"{"size":"custom"}"#))
        XCTAssertThrowsError(try create(#"{"size":"small","vcpu":3}"#))
    }

    func testBadInputIsRefusedWithTheFieldName() {
        let bad = [#"{}"#, #"{"size":"huge"}"#, #"{"size":1}"#, #"{"size":"small","wait_seconds":61}"#, #"{"size":"small","wait_seconds":-1}"#, #"{"size":"small","wait_seconds":"5"}"#,
                   #"{"size":"small","machine":"Mini"}"#, #"{"size":"small","name":"a b"}"#, #"{"size":"small","extra":1}"#, #"{"size":"small","gpu_memory_gb":0}"#,
                   #"{"size":"small","idempotency_key":"a b"}"#, #"{"size":"small","idempotency_key":""}"#, #"{"size":"custom","vcpu":0,"ram_mb":1024,"disk_gb":10}"#,
                   #"{"size":"custom","vcpu":65,"ram_mb":1024,"disk_gb":10}"#, #"{"size":"small","image":"Bad Image"}"#, "[]", "null"]
        for text in bad { XCTAssertThrowsError(try create(text), text) }
        XCTAssertThrowsError(try create(#"{"size":"small","wait_seconds":99}"#)) { error in
            XCTAssertTrue((error as? InputError)?.message.contains("wait_seconds") == true)
        }
    }

    func testVmInputs() throws {
        let start = try McpVmInput(arguments: Data(#"{"machine":"mini","vm":"wl-1","wait_seconds":5}"#.utf8), withWait: true)
        XCTAssertEqual(start.waitSeconds, 5)
        XCTAssertThrowsError(try McpVmInput(arguments: Data(#"{"machine":"mini","vm":"wl-1","wait_seconds":5}"#.utf8), withWait: false))
        XCTAssertThrowsError(try McpVmInput(arguments: Data(#"{"machine":"mini"}"#.utf8), withWait: true))
        XCTAssertThrowsError(try McpVmInput(arguments: Data(#"{"machine":"../x","vm":"wl-1"}"#.utf8), withWait: true))
    }

    func testLookupInputs() throws {
        XCTAssertEqual(try McpLookupInput.capacity(arguments: Data(#"{"machine":"mini"}"#.utf8)).machine, "mini")
        XCTAssertThrowsError(try McpLookupInput.capacity(arguments: Data("{}".utf8)))
        XCTAssertNil(try McpLookupInput.vms(arguments: Data("{}".utf8)).machine)
        XCTAssertEqual(try McpLookupInput.request(arguments: Data(#"{"request_id":"mr-abc"}"#.utf8)).requestId, "mr-abc")
        XCTAssertThrowsError(try McpLookupInput.request(arguments: Data("{}".utf8)))
        XCTAssertNoThrow(try McpLookupInput.none(arguments: Data("{}".utf8)))
        XCTAssertThrowsError(try McpLookupInput.none(arguments: Data(#"{"x":1}"#.utf8)))
    }
}

final class McpTokenRequestTests: XCTestCase {
    private func make(_ json: String) throws -> McpTokenRequest { try McpTokenRequest(body: Data(json.utf8)) }

    func testOnlyANameGivesTheDefaults() throws {
        let request = try make(#"{"name":"claude code"}"#)
        XCTAssertEqual(request.scopes, [.read, .create])
        XCTAssertEqual(request.quotas, McpQuotas.defaults)
        XCTAssertEqual(request.expiresInDays, 90)
        XCTAssertFalse(request.autoApprove)
    }

    func testEverythingGivenIsRead() throws {
        let request = try make(#"{"name":"ci","scopes":["read","destroy"],"quotas":{"max_vms":1},"expires_in_days":30,"auto_approve":true}"#)
        XCTAssertEqual(request.scopes, [.read, .destroy])
        XCTAssertEqual(request.quotas.maxVms, 1)
        XCTAssertEqual(request.expiresInDays, 30)
        XCTAssertTrue(request.autoApprove)
    }

    func testBadBodiesAreRefused() {
        let long = String(repeating: "a", count: 41)
        let bad = ["{}", #"{"name":""}"#, #"{"name":"\#(long)"}"#, #"{"name":"<b>x</b>"}"#, #"{"name":"a","scopes":[]}"#, #"{"name":"a","scopes":["root"]}"#, #"{"name":"a","expires_in_days":0}"#,
                   #"{"name":"a","expires_in_days":366}"#, #"{"name":"a","auto_approve":"yes"}"#, #"{"name":"a","quotas":{"max_vms":0}}"#, #"{"name":"a","token":"x"}"#, #"{"name":"-a"}"#]
        for text in bad { XCTAssertThrowsError(try make(text), text) }
    }

    func testAYearIsTheLongestLifetime() throws {
        XCTAssertEqual(try make(#"{"name":"a","expires_in_days":365}"#).expiresInDays, 365)
    }
}

final class McpToolSchemasTests: XCTestCase {
    private let types: Set<String> = ["string", "integer", "object", "array", "boolean", "number"]

    func testEverySchemaIsAClosedObjectWithKnownPropertyTypes() throws {
        for tool in McpTool.allCases {
            let schema = McpToolSchemas.input(of: tool)
            XCTAssertEqual(schema["type"] as? String, "object", tool.rawValue)
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false, tool.rawValue)
            let properties = try XCTUnwrap(schema["properties"] as? [String: [String: Any]], tool.rawValue)
            let required = try XCTUnwrap(schema["required"] as? [String], tool.rawValue)
            XCTAssertTrue(Set(required).isSubset(of: Set(properties.keys)), tool.rawValue)
            for (name, property) in properties {
                XCTAssertTrue(types.contains(property["type"] as? String ?? ""), "\(tool.rawValue).\(name)")
                XCTAssertFalse((property["description"] as? String ?? "").isEmpty, "\(tool.rawValue).\(name)")
            }
        }
    }

    func testEverySchemaSerializesToJson() {
        for tool in McpTool.allCases { XCTAssertTrue(JSONSerialization.isValidJSONObject(McpToolSchemas.input(of: tool)), tool.rawValue) }
    }

    func testTheCreateSchemaListsExactlyTheFieldsTheParserAccepts() throws {
        let properties = try XCTUnwrap(McpToolSchemas.input(of: .createVm)["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), McpCreateVmInput.fields)
        XCTAssertEqual(McpToolSchemas.input(of: .createVm)["required"] as? [String], ["size"])
        let size = try XCTUnwrap(properties["size"] as? [String: Any])
        XCTAssertEqual(size["enum"] as? [String], ["small", "medium", "large", "custom"])
    }

    func testTheVmSchemasMatchTheirParsers() throws {
        let start = try XCTUnwrap(McpToolSchemas.input(of: .startVm)["properties"] as? [String: Any])
        XCTAssertEqual(Set(start.keys), ["machine", "vm", "wait_seconds"])
        let delete = try XCTUnwrap(McpToolSchemas.input(of: .deleteVm)["properties"] as? [String: Any])
        XCTAssertEqual(Set(delete.keys), ["machine", "vm"])
        XCTAssertEqual((McpToolSchemas.input(of: .listMachines)["properties"] as? [String: Any])?.count, 0)
    }

    func testTheWaitRangeIsZeroTo60WithDefault30() throws {
        let properties = try XCTUnwrap(McpToolSchemas.input(of: .createVm)["properties"] as? [String: [String: Any]])
        let wait = try XCTUnwrap(properties["wait_seconds"])
        XCTAssertEqual(wait["minimum"] as? Int, 0)
        XCTAssertEqual(wait["maximum"] as? Int, 60)
        XCTAssertEqual(wait["default"] as? Int, 30)
    }
}
