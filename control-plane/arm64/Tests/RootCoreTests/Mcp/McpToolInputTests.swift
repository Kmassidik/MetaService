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

    func testANameAndAPersonGiveTheDefaults() throws {
        let request = try make(#"{"name":"laptop","person_id":"mp-ayu"}"#)
        XCTAssertEqual(request.personId, "mp-ayu")
        XCTAssertNil(request.scopes)
        XCTAssertEqual(request.expiresInDays, 90)
    }

    func testScopesAndLifetimeAreRead() throws {
        let request = try make(#"{"name":"ci","person_id":"mp-1","scopes":["read","destroy"],"expires_in_days":30}"#)
        XCTAssertEqual(request.scopes, [.read, .destroy])
        XCTAssertEqual(request.expiresInDays, 30)
        XCTAssertEqual(try make(#"{"name":"a","person_id":"mp-1","expires_in_days":365}"#).expiresInDays, 365)
    }

    func testBadBodiesAreRefused() {
        let long = String(repeating: "a", count: 41)
        let bad = [#"{"name":"a"}"#, #"{"person_id":"mp-1"}"#, #"{"name":"","person_id":"mp-1"}"#, #"{"name":"\#(long)","person_id":"mp-1"}"#, #"{"name":"<b>","person_id":"mp-1"}"#,
                   #"{"name":"a","person_id":"Mp 1"}"#, #"{"name":"a","person_id":"mp-1","scopes":[]}"#, #"{"name":"a","person_id":"mp-1","scopes":["root"]}"#,
                   #"{"name":"a","person_id":"mp-1","expires_in_days":0}"#, #"{"name":"a","person_id":"mp-1","expires_in_days":366}"#,
                   #"{"name":"a","person_id":"mp-1","quotas":{"max_vms":1}}"#, #"{"name":"a","person_id":"mp-1","auto_approve":true}"#, #"{"name":"a","person_id":"mp-1","token":"msk_x"}"#]
        for text in bad { XCTAssertThrowsError(try make(text), text) }
    }
}

final class McpPersonRequestTests: XCTestCase {
    func testAddingNeedsOnlyANameAndUsesTheDefaults() throws {
        let person = try McpPersonRequest.creating(body: Data(#"{"name":"Ayu"}"#.utf8))
        XCTAssertEqual(person.name, "Ayu")
        XCTAssertEqual(person.scopes, [.read, .create])
        XCTAssertEqual(person.quotas, McpQuotas.defaults)
    }

    func testAddingReadsScopesAndQuotas() throws {
        let person = try McpPersonRequest.creating(body: Data(#"{"name":"Budi","scopes":["read","create","gpu"],"quotas":{"max_vms":5,"gpu_memory_gb":16}}"#.utf8))
        XCTAssertEqual(person.scopes, [.read, .create, .gpu])
        XCTAssertEqual(person.quotas?.maxVms, 5)
        XCTAssertEqual(person.quotas?.gpuMemoryGb, 16)
        XCTAssertEqual(person.quotas?.maxVcpu, 8)
    }

    func testAChangeNamesScopesOrQuotasAndNeverTheName() throws {
        XCTAssertEqual(try McpPersonRequest.changing(body: Data(#"{"scopes":["read"]}"#.utf8)).scopes, [.read])
        XCTAssertEqual(try McpPersonRequest.changing(body: Data(#"{"quotas":{"max_vms":2}}"#.utf8)).quotas?.maxVms, 2)
        XCTAssertNil(try McpPersonRequest.changing(body: Data(#"{"scopes":["read"]}"#.utf8)).quotas)
        for bad in ["{}", #"{"name":"New"}"#, #"{"scopes":[]}"#, #"{"quotas":{"max_vms":0}}"#, #"{"quotas":{"nope":1}}"#, "[]"] {
            XCTAssertThrowsError(try McpPersonRequest.changing(body: Data(bad.utf8)), bad)
        }
    }

    func testBadNamesAreRefusedWhenAdding() {
        for bad in ["{}", #"{"name":""}"#, #"{"name":"<i>"}"#, #"{"name":"a","auto_approve":true}"#, #"{"name":"a","scopes":["root"]}"#] {
            XCTAssertThrowsError(try McpPersonRequest.creating(body: Data(bad.utf8)), bad)
        }
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
