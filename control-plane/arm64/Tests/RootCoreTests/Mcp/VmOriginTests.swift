import XCTest
@testable import RootCore

final class VmOriginTests: XCTestCase {
    /// A stand-in for the parent's keyed HMAC: different keys give different answers, the same key the same one.
    private func signer(_ key: String) -> (String) -> String {
        { text in Tokens.sha256Hex(key + "|" + text) }
    }

    private let mcp = VmOriginInput(kind: .mcp, actor: "mcp:Ayu", personId: "mp-1", personName: "Ayu", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code",
                                    clientVersion: "2.0.1", sourceIp: "203.0.113.9", requestId: "mr-1")

    private func record(_ input: VmOriginInput, createdAt: Int? = 1_800_000_000, backfilled: Bool = false, key: String = "k1") -> VmOriginRecord {
        let seal = VmOriginSeal.seal(machineId: "mini", workloadId: "vm-1", input: input, createdAt: createdAt, backfilled: backfilled, sign: signer(key))
        return VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: input, createdAt: createdAt, backfilled: backfilled, seal: seal)
    }

    func testTheSealIs16HexAndTheFingerprintItsFirst8() {
        let made = record(mcp)
        XCTAssertEqual(made.seal.count, 16)
        XCTAssertTrue(made.seal.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(VmOriginSeal.fingerprint(of: made.seal), String(made.seal.prefix(8)))
        XCTAssertEqual(VmOriginSeal.fingerprint(of: made.seal).count, 8)
    }

    func testAnUntouchedRecordIsIntactAndTheSameFieldsGiveTheSameSeal() {
        XCTAssertTrue(VmOriginSeal.isIntact(record(mcp), sign: signer("k1")))
        XCTAssertEqual(record(mcp).seal, record(mcp).seal)
    }

    func testAnotherKeyDoesNotVerify() {
        XCTAssertFalse(VmOriginSeal.isIntact(record(mcp, key: "other"), sign: signer("k1")))
    }

    func testChangingAnyFieldBreaksTheSeal() {
        let honest = record(mcp)
        let changes: [VmOriginRecord] = [
            VmOriginRecord(machineId: "other", workloadId: "vm-1", input: mcp, createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-2", input: mcp, createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: VmOriginInput(kind: .panel, actor: "mcp:Ayu", personId: "mp-1", personName: "Ayu", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code", clientVersion: "2.0.1", sourceIp: "203.0.113.9", requestId: "mr-1"), createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: VmOriginInput(kind: .mcp, actor: "mcp:Budi", personId: "mp-1", personName: "Ayu", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code", clientVersion: "2.0.1", sourceIp: "203.0.113.9", requestId: "mr-1"), createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: VmOriginInput(kind: .mcp, actor: "mcp:Ayu", personId: "mp-1", personName: "Budi", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code", clientVersion: "2.0.1", sourceIp: "203.0.113.9", requestId: "mr-1"), createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: VmOriginInput(kind: .mcp, actor: "mcp:Ayu", personId: "mp-1", personName: "Ayu", tokenId: "mt-1", tokenPrefix: "AbCdEfGh", clientName: "claude-code", clientVersion: "2.0.1", sourceIp: "198.51.100.1", requestId: "mr-1"), createdAt: honest.createdAt, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: mcp, createdAt: 1_800_000_001, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: mcp, createdAt: nil, seal: honest.seal),
            VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: mcp, createdAt: honest.createdAt, backfilled: true, seal: honest.seal),
        ]
        for (index, changed) in changes.enumerated() { XCTAssertFalse(VmOriginSeal.isIntact(changed, sign: signer("k1")), "change \(index)") }
    }

    func testTheDeletionNotesAreNotPartOfTheSeal() {
        let honest = record(mcp)
        let deleted = VmOriginRecord(machineId: "mini", workloadId: "vm-1", input: mcp, createdAt: honest.createdAt, deletedAt: 1_800_000_500, deletedBy: "mcp:Ayu", seal: honest.seal)
        XCTAssertTrue(VmOriginSeal.isIntact(deleted, sign: signer("k1")))
    }

    func testFieldsCannotRunIntoEachOther() {
        let one = VmOriginInput(kind: .mcp, actor: "mcp:ab", personName: "c")
        let two = VmOriginInput(kind: .mcp, actor: "mcp:a", personName: "bc")
        XCTAssertNotEqual(record(one).seal, record(two).seal)
        XCTAssertNotEqual(record(VmOriginInput(kind: .mcp, actor: "x", clientName: "")).seal, record(VmOriginInput(kind: .mcp, actor: "x", clientName: nil)).seal)
    }

    func testABackfilledRecordHasNoTimeAndItsOwnLabelAndStillVerifies() {
        let old = record(VmOriginInput(kind: .panel, actor: "admin"), createdAt: nil, backfilled: true)
        XCTAssertTrue(VmOriginSeal.isIntact(old, sign: signer("k1")))
        let short = VmCreatedBy(old, intact: true)
        XCTAssertEqual(short.label, "admin (recorded afterwards)")
        XCTAssertEqual(short.kind, "panel")
        XCTAssertEqual(short.fingerprint, VmOriginSeal.fingerprint(of: old.seal))
    }

    func testLabels() {
        XCTAssertEqual(VmCreatedBy(record(mcp), intact: true).label, "Ayu (MCP)")
        XCTAssertEqual(VmCreatedBy(record(.panel(operatorName: "kurnia", sourceIp: "127.0.0.1")), intact: true).label, "panel (kurnia)")
        XCTAssertEqual(VmCreatedBy.unknown.label, "unknown origin")
        XCTAssertNil(VmCreatedBy.unknown.fingerprint)
        XCTAssertEqual(VmCreatedBy(record(mcp), intact: false).intact, false)
    }

    func testClientText() {
        XCTAssertEqual(VmCreatedBy.clientText(mcp), "claude-code 2.0.1")
        XCTAssertEqual(VmCreatedBy.clientText(VmOriginInput(kind: .mcp, actor: "a", clientName: "cursor")), "cursor")
        XCTAssertNil(VmCreatedBy.clientText(VmOriginInput.panel(operatorName: "kurnia", sourceIp: nil)))
    }

    func testTheCreateCommandKeepsTheInputAndGivesItBack() {
        XCTAssertEqual(VmOriginInput(params: mcp.params), mcp)
        let panel = VmOriginInput.panel(operatorName: "kurnia", sourceIp: "127.0.0.1")
        XCTAssertEqual(VmOriginInput(params: panel.params), panel)
        XCTAssertNil(VmOriginInput(params: ["name": "x"]))
        XCTAssertNil(VmOriginInput(params: ["origin_kind": "bogus", "origin_actor": "a"]))
        XCTAssertNil(VmOriginInput(params: ["origin_kind": "mcp"]))
    }

    func testClientTextIsCleanedAndCut() {
        XCTAssertEqual(VmOriginInput.cleanClientText("claude-code"), "claude-code")
        XCTAssertEqual(VmOriginInput.cleanClientText("a\nb\u{7}c"), "abc")
        XCTAssertEqual(VmOriginInput.cleanClientText(String(repeating: "x", count: 200))?.count, 64)
        XCTAssertNil(VmOriginInput.cleanClientText("  "))
        XCTAssertNil(VmOriginInput.cleanClientText("\n\t"))
        XCTAssertNil(VmOriginInput.cleanClientText(nil))
    }

    func testTheShortFormEncodesWithNullFingerprintWhenUnknown() throws {
        let data = try JSONEncoder().encode(VmCreatedBy.unknown)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "unknown")
        XCTAssertTrue(object["fingerprint"] is NSNull)
        XCTAssertEqual(object["intact"] as? Bool, true)
    }
}
