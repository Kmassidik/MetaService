import XCTest
@testable import RootCore

/// Exact byte vectors, malformed-input rejection and a fixed-seed fuzz loop for the SNMP v2c codec.
final class SnmpV2cTests: XCTestCase {
    private let systemDescription = SnmpOid(dotted: "1.3.6.1.2.1.1.1.0")!
    private let getRequestBytes = hexBytes("30 26 02 01 01 04 06 70 75 62 6c 69 63 a0 19 02 01 01 02 01 00 02 01 00 30 0e 30 0c 06 08 2b 06 01 02 01 01 01 00 05 00")
    private let getResponseBytes = hexBytes("30 2b 02 01 01 04 06 70 75 62 6c 69 63 a2 1e 02 01 01 02 01 00 02 01 00 30 13 30 11 06 08 2b 06 01 02 01 01 01 00 04 05 4c 69 6e 75 78")

    private let fuzzSeed: UInt64 = 20261114
    private let fuzzIterations = 2000
    private let fuzzMaxLength = 96

    func testEncodesKnownGetRequestExactly() {
        let bytes = SnmpV2c.encodeRequest(kind: .get, community: "public", requestId: 1, oids: [systemDescription])
        XCTAssertEqual(bytes, getRequestBytes)
    }

    func testDecodesKnownGetResponse() throws {
        let decoded = try SnmpV2c.decodeResponse(getResponseBytes)
        XCTAssertEqual(decoded.requestId, 1)
        XCTAssertEqual(decoded.errorStatus, 0)
        XCTAssertEqual(decoded.varbinds, [SnmpVarbind(oid: systemDescription, value: .octets(Array("Linux".utf8)))])
    }

    func testCounter64DecodesFromEightBytes() throws {
        let value = try decodeSingleValue(BerWriter.element(BerTag.counter64, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
        XCTAssertEqual(value, .counter64(0x0102_0304_0506_0708))
    }

    func testCounter64DecodesFromThreeBytes() throws {
        let value = try decodeSingleValue(BerWriter.element(BerTag.counter64, [0x12, 0x34, 0x56]))
        XCTAssertEqual(value, .counter64(0x123456))
    }

    func testCounter32IgnoresLeadingZeroByte() throws {
        let value = try decodeSingleValue(BerWriter.element(BerTag.counter32, [0x00, 0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertEqual(value, .unsigned32(UInt32.max))
    }

    func testNoSuchInstanceDecodes() throws {
        let value = try decodeSingleValue([BerTag.noSuchInstance, 0x00])
        XCTAssertEqual(value, .noSuchInstance)
    }

    func testRequestWithTwoOidsCarriesBoth() throws {
        let second = SnmpOid(dotted: "1.3.6.1.2.1.2.1.0")!
        let bytes = SnmpV2c.encodeRequest(kind: .getNext, community: "public", requestId: 7, oids: [systemDescription, second])
        let fields = try requestFields(bytes)
        XCTAssertEqual(fields.requestId, 7)
        XCTAssertEqual(fields.oids, [systemDescription, second])
        XCTAssertEqual(fields.pduTag, BerTag.getNextRequest)
    }

    func testLongFormLengthCarriesTwoHundredByteOctets() throws {
        let payload = (0..<200).map { UInt8(truncatingIfNeeded: $0) }
        let bytes = makeResponse(requestId: 1, bindings: [encodedVarbind(systemDescription, BerWriter.octets(payload))])
        XCTAssertNotNil(bytes.firstRange(of: [BerTag.octetString, 0x81, 0xC8]))
        let value = try decodeSingleValue(BerWriter.octets(payload))
        XCTAssertEqual(value, .octets(payload))
    }

    func testRandomRequestsRoundTrip() throws {
        var random = SnmpTestRandom(seed: fuzzSeed)
        for requestId in Int32(1)...50 {
            let oids = (0...random.below(4)).map { _ in randomOid(&random) }
            let bytes = SnmpV2c.encodeRequest(kind: .get, community: "public", requestId: requestId, oids: oids)
            let fields = try requestFields(bytes)
            XCTAssertEqual(fields.requestId, requestId)
            XCTAssertEqual(fields.oids, oids)
        }
    }

    func testRejectsGetRequestWhereResponseIsExpected() {
        XCTAssertThrowsError(try SnmpV2c.decodeResponse(getRequestBytes))
    }

    func testRejectsEveryTruncationOfKnownResponse() {
        for length in 0..<getResponseBytes.count {
            XCTAssertThrowsError(try SnmpV2c.decodeResponse(Array(getResponseBytes.prefix(length))), "length \(length)")
        }
    }

    func testRejectsLengthThatRunsPastTheEnd() {
        XCTAssertThrowsError(try SnmpV2c.decodeResponse([BerTag.sequence, 0x10, 0x02, 0x01, 0x01]))
    }

    func testRejectsVersionOtherThanV2c() {
        var bytes = getResponseBytes
        bytes[4] = 0x00
        XCTAssertThrowsError(try SnmpV2c.decodeResponse(bytes))
    }

    func testRejectsMoreVarbindsThanTheLimit() {
        let binding = encodedVarbind(systemDescription, BerWriter.null())
        let bindings = [[UInt8]](repeating: binding, count: SnmpLimits.maxVarbinds + 1)
        XCTAssertThrowsError(try SnmpV2c.decodeResponse(makeResponse(requestId: 1, bindings: bindings)))
    }

    func testRejectsOctetStringOverTheLimit() {
        let payload = [UInt8](repeating: 0, count: SnmpLimits.maxOctetBytes + 1)
        XCTAssertThrowsError(try decodeSingleValue(BerWriter.octets(payload)))
    }

    func testRejectsOidWithMoreArcsThanTheLimit() {
        let oidContents: [UInt8] = [0x2B] + [UInt8](repeating: 0x01, count: SnmpLimits.maxOidArcs - 1)
        let binding = BerWriter.element(BerTag.sequence, BerWriter.element(BerTag.objectIdentifier, oidContents) + BerWriter.null())
        XCTAssertThrowsError(try SnmpV2c.decodeResponse(makeResponse(requestId: 1, bindings: [binding])))
    }

    func testRejectsEmptyAndTruncatedOidContents() {
        XCTAssertThrowsError(try decodeSingleValueOid([]))
        XCTAssertThrowsError(try decodeSingleValueOid([0x2B, 0x81]))
    }

    func testRandomBytesNeverCrashTheDecoder() {
        var random = SnmpTestRandom(seed: fuzzSeed)
        var rejected = 0
        for _ in 0..<fuzzIterations {
            let bytes = random.bytes(count: random.below(fuzzMaxLength + 1))
            if (try? SnmpV2c.decodeResponse(bytes)) == nil {
                rejected += 1
            }
        }
        XCTAssertGreaterThan(rejected, 0)
    }

    func testEveryTruncationOfKnownResponseReturnsOrThrows() {
        var returned = 0
        for length in 0...getResponseBytes.count {
            if (try? SnmpV2c.decodeResponse(Array(getResponseBytes.prefix(length)))) != nil {
                returned += 1
            }
        }
        XCTAssertEqual(returned, 1)
    }

    /// Decodes one varbind whose value is `valueBytes` and returns that value.
    private func decodeSingleValue(_ valueBytes: [UInt8]) throws -> SnmpValue {
        let bytes = makeResponse(requestId: 1, bindings: [encodedVarbind(systemDescription, valueBytes)])
        return try SnmpV2c.decodeResponse(bytes).varbinds[0].value
    }

    /// Decodes a response whose only varbind carries an OID with the given raw contents.
    private func decodeSingleValueOid(_ oidContents: [UInt8]) throws -> SnmpVarbind {
        let binding = BerWriter.element(BerTag.sequence, BerWriter.element(BerTag.objectIdentifier, oidContents) + BerWriter.null())
        return try SnmpV2c.decodeResponse(makeResponse(requestId: 1, bindings: [binding])).varbinds[0]
    }

    /// A valid random OID: a legal root pair followed by one to four arcs up to about 2^20.
    private func randomOid(_ random: inout SnmpTestRandom) -> SnmpOid {
        let root = UInt32(random.below(3))
        let second = UInt32(random.below(root == 2 ? 200 : 40))
        let tail = (0...random.below(3)).map { _ in UInt32(random.below(1 << 20)) }
        return SnmpOid(arcs: [root, second] + tail)!
    }
}
