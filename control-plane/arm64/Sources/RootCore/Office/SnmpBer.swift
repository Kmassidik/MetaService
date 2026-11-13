import Foundation

/// BER tags used by SNMP v2c: universal types, SNMP application types and PDU types.
enum BerTag {
    static let integer: UInt8 = 0x02
    static let octetString: UInt8 = 0x04
    static let null: UInt8 = 0x05
    static let objectIdentifier: UInt8 = 0x06
    static let sequence: UInt8 = 0x30
    static let counter32: UInt8 = 0x41
    static let gauge32: UInt8 = 0x42
    static let counter64: UInt8 = 0x46
    static let noSuchObject: UInt8 = 0x80
    static let noSuchInstance: UInt8 = 0x81
    static let endOfMibView: UInt8 = 0x82
    static let getRequest: UInt8 = 0xA0
    static let getNextRequest: UInt8 = 0xA1
    static let getResponse: UInt8 = 0xA2
}

/// Sizes and bit masks used by the BER encoder and decoder.
enum BerLimits {
    static let shortFormMaxLength = 127
    static let longFormFlag: UInt8 = 0x80
    static let longFormMaxBytes = 4
    static let integerMaxBytes = 8
    static let counter32MaxBytes = 4
    static let counter64MaxBytes = 8
    static let base128Bits = 7
    static let base128Mask: UInt8 = 0x7F
    static let base128Continuation: UInt8 = 0x80
    static let signBit: UInt8 = 0x80
    static let zeroByte: UInt8 = 0x00
    static let allOnesByte: UInt8 = 0xFF
    static let byteBits = 8
}

/// Reads BER elements from a byte slice in order. Every read checks the remaining length before it touches a byte.
struct BerReader {
    private var rest: ArraySlice<UInt8>

    /// Starts reading at the first byte of `bytes`.
    init(_ bytes: ArraySlice<UInt8>) {
        rest = bytes
    }

    /// True when every byte has been read.
    var isAtEnd: Bool {
        rest.isEmpty
    }

    /// Reads the next element of any tag and returns its tag and contents.
    mutating func nextElement() throws -> (tag: UInt8, body: ArraySlice<UInt8>) {
        guard let tag = rest.first else {
            throw SnmpError.badResponse("truncated tag")
        }
        rest = rest.dropFirst()
        let length = try readLength()
        guard length <= rest.count else {
            throw SnmpError.badResponse("length runs past the end")
        }
        let body = rest.prefix(length)
        rest = rest.dropFirst(length)
        return (tag, body)
    }

    /// Reads the next element, requires the tag `expected`, and returns its contents.
    mutating func expect(_ expected: UInt8) throws -> ArraySlice<UInt8> {
        let element = try nextElement()
        guard element.tag == expected else {
            throw SnmpError.badResponse("unexpected tag")
        }
        return element.body
    }

    /// Like `expect`, but returns a reader over the contents so nested fields can be read in turn.
    mutating func expectSequence(_ expected: UInt8) throws -> BerReader {
        let body = try expect(expected)
        return BerReader(body)
    }

    /// Reads a definite length: short form below 128, or 0x80 plus a byte count and that many length bytes.
    private mutating func readLength() throws -> Int {
        guard let first = rest.first else {
            throw SnmpError.badResponse("truncated length")
        }
        rest = rest.dropFirst()
        guard (first & BerLimits.longFormFlag) != 0 else {
            return Int(first)
        }
        let byteCount = Int(first & ~BerLimits.longFormFlag)
        guard (1...BerLimits.longFormMaxBytes).contains(byteCount), byteCount <= rest.count else {
            throw SnmpError.badResponse("unsupported length form")
        }
        let length = rest.prefix(byteCount).reduce(0) { ($0 << BerLimits.byteBits) | Int($1) }
        rest = rest.dropFirst(byteCount)
        return length
    }
}

/// Writes BER elements with definite lengths and minimal two's complement integers.
enum BerWriter {
    /// Wraps `contents` in a tag and a length.
    static func element(_ tag: UInt8, _ contents: [UInt8]) -> [UInt8] {
        [tag] + lengthBytes(contents.count) + contents
    }

    /// Short form below 128. Otherwise 0x80 | byte count, followed by the big-endian length.
    static func lengthBytes(_ count: Int) -> [UInt8] {
        guard count > BerLimits.shortFormMaxLength else {
            return [UInt8(truncatingIfNeeded: count)]
        }
        var digits: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            digits.insert(UInt8(truncatingIfNeeded: remaining), at: 0)
            remaining >>= BerLimits.byteBits
        }
        return [BerLimits.longFormFlag | UInt8(digits.count)] + digits
    }

    /// An INTEGER element holding `value`.
    static func integer(_ value: Int64) -> [UInt8] {
        element(BerTag.integer, integerContents(value))
    }

    /// Big-endian two's complement with redundant leading sign bytes removed.
    static func integerContents(_ value: Int64) -> [UInt8] {
        var bytes = (0..<BerLimits.integerMaxBytes).reversed().map { shift in
            UInt8(truncatingIfNeeded: value >> (shift * BerLimits.byteBits))
        }
        while bytes.count > 1 && isRedundantSignByte(bytes[0], next: bytes[1]) {
            bytes.removeFirst()
        }
        return bytes
    }

    /// A leading byte is redundant when the byte after it already has the same sign.
    private static func isRedundantSignByte(_ lead: UInt8, next: UInt8) -> Bool {
        let nextIsNegative = (next & BerLimits.signBit) != 0
        let positiveRun = lead == BerLimits.zeroByte && !nextIsNegative
        let negativeRun = lead == BerLimits.allOnesByte && nextIsNegative
        return positiveRun || negativeRun
    }

    /// An OCTET STRING element.
    static func octets(_ bytes: [UInt8]) -> [UInt8] {
        element(BerTag.octetString, bytes)
    }

    /// A NULL element.
    static func null() -> [UInt8] {
        element(BerTag.null, [])
    }

    /// An OBJECT IDENTIFIER element.
    static func oid(_ oid: SnmpOid) -> [UInt8] {
        element(BerTag.objectIdentifier, oidContents(oid))
    }

    /// The first two arcs share one sub-identifier (arc1 * 40 + arc2). Every other arc is its own sub-identifier.
    private static func oidContents(_ oid: SnmpOid) -> [UInt8] {
        let firstArcSpan = UInt64(SnmpOid.firstArcSpan)
        let rootValue = UInt64(oid.arcs[0]) * firstArcSpan + UInt64(oid.arcs[1])
        let subIdentifiers = [rootValue] + oid.arcs.dropFirst(2).map { UInt64($0) }
        return subIdentifiers.flatMap { base128($0) }
    }

    /// Base-128 digits, most significant first. Every byte except the last has the high bit set.
    static func base128(_ value: UInt64) -> [UInt8] {
        var digits = [UInt8(truncatingIfNeeded: value) & BerLimits.base128Mask]
        var remaining = value >> BerLimits.base128Bits
        while remaining > 0 {
            let digit = UInt8(truncatingIfNeeded: remaining) & BerLimits.base128Mask
            digits.insert(digit | BerLimits.base128Continuation, at: 0)
            remaining >>= BerLimits.base128Bits
        }
        return digits
    }
}

/// Turns BER element contents into integers, OIDs and octets. Each check runs before the bytes are used.
enum BerDecode {
    /// A signed two's complement integer of 1 to 8 bytes.
    static func signed(_ body: ArraySlice<UInt8>) throws -> Int64 {
        guard let first = body.first, body.count <= BerLimits.integerMaxBytes else {
            throw SnmpError.badResponse("integer size")
        }
        var value: Int64 = (first & BerLimits.signBit) != 0 ? -1 : 0
        for byte in body {
            value = (value << BerLimits.byteBits) | Int64(byte)
        }
        return value
    }

    /// A signed integer that must fit in Int32 (SNMP request ids).
    static func int32(_ body: ArraySlice<UInt8>) throws -> Int32 {
        let number = try signed(body)
        guard let value = Int32(exactly: number) else {
            throw SnmpError.badResponse("request id out of range")
        }
        return value
    }

    /// An unsigned value with at most `maxBytes` significant bytes. Leading zero bytes are ignored.
    static func unsigned(_ body: ArraySlice<UInt8>, maxBytes: Int) throws -> UInt64 {
        guard !body.isEmpty else {
            throw SnmpError.badResponse("empty unsigned value")
        }
        let significant = body.drop(while: { $0 == BerLimits.zeroByte })
        guard significant.count <= maxBytes else {
            throw SnmpError.badResponse("unsigned value too long")
        }
        return significant.reduce(UInt64(0)) { ($0 << BerLimits.byteBits) | UInt64($1) }
    }

    /// Counter32 or Gauge32 value.
    static func unsigned32(_ body: ArraySlice<UInt8>) throws -> UInt32 {
        let value = try unsigned(body, maxBytes: BerLimits.counter32MaxBytes)
        guard let number = UInt32(exactly: value) else {
            throw SnmpError.badResponse("counter32 out of range")
        }
        return number
    }

    /// Counter64 value.
    static func unsigned64(_ body: ArraySlice<UInt8>) throws -> UInt64 {
        try unsigned(body, maxBytes: BerLimits.counter64MaxBytes)
    }

    /// Octet string contents, capped at `SnmpLimits.maxOctetBytes`.
    static func octets(_ body: ArraySlice<UInt8>) throws -> [UInt8] {
        guard body.count <= SnmpLimits.maxOctetBytes else {
            throw SnmpError.badResponse("octet string too long")
        }
        return Array(body)
    }

    /// Fails unless the contents are empty (NULL and the exception values have no contents).
    static func requireEmpty(_ body: ArraySlice<UInt8>) throws {
        guard body.isEmpty else {
            throw SnmpError.badResponse("value with contents where none is allowed")
        }
    }

    /// An OBJECT IDENTIFIER: base-128 sub-identifiers, with the first one split into two arcs.
    static func objectIdentifier(_ body: ArraySlice<UInt8>) throws -> SnmpOid {
        let subIdentifiers = try base128Values(body)
        guard let root = subIdentifiers.first else {
            throw SnmpError.badResponse("empty object identifier")
        }
        let rootPair = try rootArcs(root)
        let tailArcs = try subIdentifiers.dropFirst().map { try arcValue($0) }
        guard let oid = SnmpOid(arcs: rootPair + tailArcs) else {
            throw SnmpError.badResponse("invalid object identifier")
        }
        return oid
    }

    /// Splits the first sub-identifier back into its two arcs.
    private static func rootArcs(_ value: UInt64) throws -> [UInt32] {
        let span = UInt64(SnmpOid.firstArcSpan)
        let root = min(value / span, 2)
        let second = try arcValue(value - root * span)
        return [UInt32(root), second]
    }

    /// Converts one sub-identifier to an arc, failing when it does not fit in 32 bits.
    private static func arcValue(_ value: UInt64) throws -> UInt32 {
        guard let arc = UInt32(exactly: value) else {
            throw SnmpError.badResponse("arc too large")
        }
        return arc
    }

    /// Reads base-128 sub-identifiers. Fails when the last byte still says "more follows" or a value would overflow 64 bits.
    private static func base128Values(_ body: ArraySlice<UInt8>) throws -> [UInt64] {
        guard let last = body.last, (last & BerLimits.base128Continuation) == 0 else {
            throw SnmpError.badResponse("object identifier ends inside an arc")
        }
        let overflowShift = UInt64.bitWidth - BerLimits.base128Bits
        var values: [UInt64] = []
        var current: UInt64 = 0
        for byte in body {
            guard (current >> overflowShift) == 0 else {
                throw SnmpError.badResponse("arc overflows 64 bits")
            }
            current = (current << BerLimits.base128Bits) | UInt64(byte & BerLimits.base128Mask)
            if (byte & BerLimits.base128Continuation) == 0 {
                values.append(current)
                current = 0
            }
        }
        return values
    }
}
