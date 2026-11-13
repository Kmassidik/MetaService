import XCTest
@testable import RootCore

/// Fake transport that answers with a prepared function, so the client is tested without any socket.
struct FakeSnmpTransport: SnmpTransport {
    let reply: @Sendable ([UInt8]) throws -> [UInt8]

    func exchange(_ request: [UInt8], timeout: TimeInterval) async throws -> [UInt8] {
        try reply(request)
    }
}

/// Error thrown by the fake transport to simulate an unreachable agent.
enum FakeFailure: Error {
    case unreachable
}

/// One OID in the fake agent's table, with its encoded value element.
struct FakeEntry: Sendable {
    let oid: SnmpOid
    let valueBytes: [UInt8]
}

/// Builds a fake agent that answers from a sorted table: GET by exact OID, GETNEXT with the next OID.
/// `requestIdShift` changes the reply id, and `errorStatus` sets the reply's error status.
func fakeAgent(table: [FakeEntry], requestIdShift: Int32 = 0, errorStatus: Int = 0) -> @Sendable ([UInt8]) throws -> [UInt8] {
    return { request in
        let fields = try requestFields(request)
        let answers: [FakeEntry]
        if fields.pduTag == BerTag.getNextRequest {
            answers = fields.oids.map { nextAnswer(after: $0, in: table) }
        } else {
            answers = fields.oids.map { exactAnswer(for: $0, in: table) }
        }
        let bindings = answers.map { encodedVarbind($0.oid, $0.valueBytes) }
        return makeResponse(requestId: fields.requestId &+ requestIdShift, errorStatus: errorStatus, bindings: bindings)
    }
}

/// The table entry for `oid`, or noSuchObject when the agent has none.
func exactAnswer(for oid: SnmpOid, in table: [FakeEntry]) -> FakeEntry {
    table.first { $0.oid == oid } ?? FakeEntry(oid: oid, valueBytes: BerWriter.element(BerTag.noSuchObject, []))
}

/// The first table entry after `cursor`, or endOfMibView when the table has none left.
func nextAnswer(after cursor: SnmpOid, in table: [FakeEntry]) -> FakeEntry {
    table.first { cursor.arcs.lexicographicallyPrecedes($0.oid.arcs) }
        ?? FakeEntry(oid: cursor, valueBytes: BerWriter.element(BerTag.endOfMibView, []))
}

/// Client tests over the fake transport: GET, GETNEXT walks, and every error path.
final class SnmpClientTests: XCTestCase {
    private let ifDescrPrefix = SnmpOid(dotted: "1.3.6.1.2.1.2.2.1.2")!
    private let interfaceNames = ["lan", "wan1", "wan2", "wlan", "vpn"]
    private let sysName = SnmpOid(dotted: "1.3.6.1.2.1.1.5.0")!
    private let community = "public"

    /// The ifDescr rows (.2.1 to .2.5), then an ifType row outside the subtree.
    private var table: [FakeEntry] {
        let rows = interfaceNames.enumerated().map { index, name in
            FakeEntry(oid: SnmpOid(arcs: ifDescrPrefix.arcs + [UInt32(index + 1)])!, valueBytes: BerWriter.octets(Array(name.utf8)))
        }
        let outside = FakeEntry(oid: SnmpOid(dotted: "1.3.6.1.2.1.2.2.1.3.1")!, valueBytes: BerWriter.integer(6))
        return rows + [outside]
    }

    func testGetReturnsEveryRequestedValue() async throws {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table)), community: community)
        let first = SnmpOid(arcs: ifDescrPrefix.arcs + [1])!
        let second = SnmpOid(arcs: ifDescrPrefix.arcs + [2])!
        let values = try await client.get([first, second])
        XCTAssertEqual(values, [
            SnmpVarbind(oid: first, value: .octets(Array("lan".utf8))),
            SnmpVarbind(oid: second, value: .octets(Array("wan1".utf8))),
        ])
    }

    func testGetOfMissingOidReturnsNoSuchObject() async throws {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table)), community: community)
        let values = try await client.get([sysName])
        XCTAssertEqual(values, [SnmpVarbind(oid: sysName, value: .noSuchObject)])
    }

    func testWalkReturnsExactlyTheSubtreeAndStopsAtItsEnd() async throws {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table)), community: community)
        let rows = try await client.walk(ifDescrPrefix, maxEntries: 100)
        XCTAssertEqual(rows.count, interfaceNames.count)
        XCTAssertEqual(rows.map(\.value), interfaceNames.map { SnmpValue.octets(Array($0.utf8)) })
        XCTAssertTrue(rows.allSatisfy { $0.oid.hasPrefix(ifDescrPrefix) })
    }

    func testWalkStopsAtMaxEntries() async throws {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table)), community: community)
        let rows = try await client.walk(ifDescrPrefix, maxEntries: 2)
        XCTAssertEqual(rows.count, 2)
    }

    func testTransportFailureSurfacesAsTransportFailed() async {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: { _ in throw FakeFailure.unreachable }), community: community)
        await assertSnmpFailure(.transportFailed("unreachable")) {
            try await client.get([sysName])
        }
    }

    func testWrongRequestIdIsMismatched() async {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table, requestIdShift: 1)), community: community)
        await assertSnmpFailure(.mismatchedRequest) {
            try await client.get([sysName])
        }
    }

    func testAgentErrorStatusIsReported() async {
        let client = SnmpClient(transport: FakeSnmpTransport(reply: fakeAgent(table: table, errorStatus: 2)), community: community)
        await assertSnmpFailure(.agentError(2)) {
            try await client.get([sysName])
        }
    }

    /// Runs `operation` and checks that it throws exactly `expected`.
    private func assertSnmpFailure(
        _ expected: SnmpError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> [SnmpVarbind]
    ) async {
        do {
            _ = try await operation()
            XCTFail("expected \(expected) but the call returned", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SnmpError, expected, file: file, line: line)
        }
    }
}
