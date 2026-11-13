import Foundation
@testable import RootCore

/// Parses space-separated hex bytes such as "30 26 02 01".
func hexBytes(_ text: String) -> [UInt8] {
    text.split(separator: " ").map { UInt8($0, radix: 16)! }
}

/// Fixed-seed pseudo-random numbers, so every run sees the same inputs.
struct SnmpTestRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Next value from a linear congruential generator, shifted to drop the weak low bits.
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }

    /// A value in 0..<bound.
    mutating func below(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// A random byte array of the given length.
    mutating func bytes(count: Int) -> [UInt8] {
        (0..<count).map { _ in UInt8(truncatingIfNeeded: next()) }
    }
}

/// Builds one encoded varbind: SEQUENCE { OID, value }. `valueBytes` is a complete encoded value element.
func encodedVarbind(_ oid: SnmpOid, _ valueBytes: [UInt8]) -> [UInt8] {
    BerWriter.element(BerTag.sequence, BerWriter.oid(oid) + valueBytes)
}

/// Builds a GetResponse for `requestId`. Each binding is one encoded varbind.
func makeResponse(requestId: Int32, errorStatus: Int = 0, bindings: [[UInt8]]) -> [UInt8] {
    let variables = BerWriter.element(BerTag.sequence, bindings.flatMap { $0 })
    let pduContents = BerWriter.integer(Int64(requestId))
        + BerWriter.integer(Int64(errorStatus))
        + BerWriter.integer(0)
        + variables
    let pdu = BerWriter.element(BerTag.getResponse, pduContents)
    let message = BerWriter.integer(SnmpLimits.snmpVersionV2c)
        + BerWriter.octets(Array("public".utf8))
        + pdu
    return BerWriter.element(BerTag.sequence, message)
}

/// Reads back a request built by the encoder: its request id, its OIDs and its PDU tag.
func requestFields(_ bytes: [UInt8]) throws -> (requestId: Int32, oids: [SnmpOid], pduTag: UInt8) {
    var message = BerReader(bytes[...])
    var fields = try message.expectSequence(BerTag.sequence)
    _ = try fields.expect(BerTag.integer)
    _ = try fields.expect(BerTag.octetString)
    let pduElement = try fields.nextElement()
    var pdu = BerReader(pduElement.body)
    let requestId = try BerDecode.int32(pdu.expect(BerTag.integer))
    _ = try pdu.expect(BerTag.integer)
    _ = try pdu.expect(BerTag.integer)
    var list = try pdu.expectSequence(BerTag.sequence)
    var oids: [SnmpOid] = []
    while !list.isAtEnd {
        var pair = try list.expectSequence(BerTag.sequence)
        oids.append(try BerDecode.objectIdentifier(pair.expect(BerTag.objectIdentifier)))
    }
    return (requestId, oids, pduElement.tag)
}
