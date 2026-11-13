import Foundation

/// Limits enforced by the SNMP v2c decoder and by the walk.
public enum SnmpLimits {
    /// Most varbinds accepted in one response.
    public static let maxVarbinds = 64
    /// Most arcs accepted in one OID.
    public static let maxOidArcs = 128
    /// Longest octet string accepted in a value.
    public static let maxOctetBytes = 1024
    /// Most entries one walk returns, whatever the caller asks for.
    public static let maxWalkEntries = 512
    /// The version field value for SNMP v2c.
    static let snmpVersionV2c: Int64 = 1
}

/// An object identifier such as 1.3.6.1.2.1.1.1.0. Always has at least two arcs and at most `SnmpLimits.maxOidArcs`.
public struct SnmpOid: Equatable, Hashable, Sendable {
    /// The first arc may be 0, 1 or 2; under 0 and 1 the second arc is below this span.
    static let firstArcSpan: UInt32 = 40

    public let arcs: [UInt32]

    /// Returns nil when the arcs break the rules: count, first arc above 2, or second arc too large under root 0 or 1.
    public init?(arcs: [UInt32]) {
        guard (2...SnmpLimits.maxOidArcs).contains(arcs.count) else {
            return nil
        }
        let root = arcs[0]
        guard root <= 2, root == 2 || arcs[1] < SnmpOid.firstArcSpan else {
            return nil
        }
        self.arcs = arcs
    }

    /// Parses dotted text such as "1.3.6.1.2.1.1.1.0". Returns nil for anything else.
    public init?(dotted text: String) {
        var arcs: [UInt32] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let arc = UInt32(part) else {
                return nil
            }
            arcs.append(arc)
        }
        self.init(arcs: arcs)
    }

    /// The dotted form, for example "1.3.6.1".
    public var dotted: String {
        arcs.map { String($0) }.joined(separator: ".")
    }

    /// True when `other` is this OID or one of its parents, for example 1.3.6 is a prefix of 1.3.6.1.2.
    public func hasPrefix(_ other: SnmpOid) -> Bool {
        arcs.starts(with: other.arcs)
    }
}

/// One SNMP value. The exception cases (noSuchObject and the others) carry no data.
public enum SnmpValue: Equatable, Sendable {
    case integer(Int64)
    /// Counter32 (tag 0x41) or Gauge32 (tag 0x42).
    case unsigned32(UInt32)
    /// Counter64 (tag 0x46).
    case counter64(UInt64)
    case octets([UInt8])
    case oid(SnmpOid)
    case null
    case noSuchObject
    case noSuchInstance
    case endOfMibView
}

/// One OID with its value, as carried in a GET or GETNEXT answer.
public struct SnmpVarbind: Equatable, Sendable {
    public let oid: SnmpOid
    public let value: SnmpValue

    public init(oid: SnmpOid, value: SnmpValue) {
        self.oid = oid
        self.value = value
    }
}

/// The two request PDUs this client sends.
public enum SnmpPduKind: Sendable {
    case get
    case getNext

    /// The PDU tag: 0xA0 for GET, 0xA1 for GETNEXT.
    var tag: UInt8 {
        switch self {
        case .get:
            return BerTag.getRequest
        case .getNext:
            return BerTag.getNextRequest
        }
    }
}

/// SNMP v2c messages: builds GET and GETNEXT requests and reads GetResponse messages.
public enum SnmpV2c {
    /// Error status value meaning "no error".
    public static let noErrorStatus = 0

    /// Error status and error index fields of a request, which are always zero.
    private static let unusedRequestField: Int64 = 0

    /// Builds a complete SNMP v2c request. The community is written as given; callers must keep it out of logs.
    public static func encodeRequest(kind: SnmpPduKind, community: String, requestId: Int32, oids: [SnmpOid]) -> [UInt8] {
        let bindings = oids.flatMap { oid in
            BerWriter.element(BerTag.sequence, BerWriter.oid(oid) + BerWriter.null())
        }
        let variables = BerWriter.element(BerTag.sequence, bindings)
        let pduContents = BerWriter.integer(Int64(requestId))
            + BerWriter.integer(unusedRequestField)
            + BerWriter.integer(unusedRequestField)
            + variables
        let pdu = BerWriter.element(kind.tag, pduContents)
        let messageContents = BerWriter.integer(SnmpLimits.snmpVersionV2c)
            + BerWriter.octets(Array(community.utf8))
            + pdu
        return BerWriter.element(BerTag.sequence, messageContents)
    }

    /// Reads a GetResponse. Rejects truncated input, wrong tags, a wrong version, and anything over the limits.
    public static func decodeResponse(_ bytes: [UInt8]) throws -> (requestId: Int32, errorStatus: Int, varbinds: [SnmpVarbind]) {
        var message = BerReader(bytes[...])
        var fields = try message.expectSequence(BerTag.sequence)
        guard message.isAtEnd else {
            throw SnmpError.badResponse("bytes after the message")
        }
        let version = try BerDecode.signed(fields.expect(BerTag.integer))
        guard version == SnmpLimits.snmpVersionV2c else {
            throw SnmpError.badResponse("not SNMP v2c")
        }
        _ = try fields.expect(BerTag.octetString)
        var pdu = try fields.expectSequence(BerTag.getResponse)
        guard fields.isAtEnd else {
            throw SnmpError.badResponse("bytes after the PDU")
        }
        let requestId = try BerDecode.int32(pdu.expect(BerTag.integer))
        let errorStatus = try decodeErrorStatus(pdu.expect(BerTag.integer))
        _ = try pdu.expect(BerTag.integer)
        var list = try pdu.expectSequence(BerTag.sequence)
        guard pdu.isAtEnd else {
            throw SnmpError.badResponse("bytes after the varbind list")
        }
        let varbinds = try decodeVarbinds(&list)
        return (requestId, errorStatus, varbinds)
    }

    /// The error status is a small integer. Anything outside Int is rejected.
    private static func decodeErrorStatus(_ body: ArraySlice<UInt8>) throws -> Int {
        let status = try BerDecode.signed(body)
        guard let value = Int(exactly: status) else {
            throw SnmpError.badResponse("error status out of range")
        }
        return value
    }

    /// Reads every varbind in the list, failing past `SnmpLimits.maxVarbinds`.
    private static func decodeVarbinds(_ list: inout BerReader) throws -> [SnmpVarbind] {
        var varbinds: [SnmpVarbind] = []
        while !list.isAtEnd {
            guard varbinds.count < SnmpLimits.maxVarbinds else {
                throw SnmpError.badResponse("too many varbinds")
            }
            varbinds.append(try decodeVarbind(&list))
        }
        return varbinds
    }

    /// Reads one SEQUENCE { OID, value }.
    private static func decodeVarbind(_ list: inout BerReader) throws -> SnmpVarbind {
        var pair = try list.expectSequence(BerTag.sequence)
        let oid = try BerDecode.objectIdentifier(pair.expect(BerTag.objectIdentifier))
        let element = try pair.nextElement()
        guard pair.isAtEnd else {
            throw SnmpError.badResponse("bytes after the varbind value")
        }
        let value = try decodeValue(tag: element.tag, body: element.body)
        return SnmpVarbind(oid: oid, value: value)
    }

    /// Maps a value tag to an `SnmpValue`. Unknown tags (for example TimeTicks) are rejected.
    static func decodeValue(tag: UInt8, body: ArraySlice<UInt8>) throws -> SnmpValue {
        switch tag {
        case BerTag.integer:
            return .integer(try BerDecode.signed(body))
        case BerTag.octetString:
            return .octets(try BerDecode.octets(body))
        case BerTag.objectIdentifier:
            return .oid(try BerDecode.objectIdentifier(body))
        case BerTag.counter32, BerTag.gauge32:
            return .unsigned32(try BerDecode.unsigned32(body))
        case BerTag.counter64:
            return .counter64(try BerDecode.unsigned64(body))
        case BerTag.null:
            return try emptyValue(.null, body)
        case BerTag.noSuchObject:
            return try emptyValue(.noSuchObject, body)
        case BerTag.noSuchInstance:
            return try emptyValue(.noSuchInstance, body)
        case BerTag.endOfMibView:
            return try emptyValue(.endOfMibView, body)
        default:
            throw SnmpError.badResponse("unsupported value type")
        }
    }

    /// Returns `value` after checking that the element has no contents.
    private static func emptyValue(_ value: SnmpValue, _ body: ArraySlice<UInt8>) throws -> SnmpValue {
        try BerDecode.requireEmpty(body)
        return value
    }
}
