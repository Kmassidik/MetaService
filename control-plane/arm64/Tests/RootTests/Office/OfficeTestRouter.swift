import Foundation
@testable import RootCore

/// A fake Omada router for the sampler tests. It answers GET for the WAN counters and GETNEXT for the names table, from memory only.
/// It can be switched to 32-bit counters only (the 64-bit ones answer noSuchInstance) or to not answering at all. Nothing touches the network.
final class FakeOfficeRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var counters: [Int: (inBytes: UInt64, outBytes: UInt64)] = [:]
    private var names: [Int: String] = [:]
    private var wideSupported = true
    private var timesOut = false

    /// Sets the counters of one WAN index (the values are kept as 64-bit numbers).
    func setCounters(index: Int, inBytes: UInt64, outBytes: UInt64) {
        lock.withLock { counters[index] = (inBytes, outBytes) }
    }

    func setNames(_ table: [Int: String]) {
        lock.withLock { names = table }
    }

    /// False: the router only has 32-bit counters, so the 64-bit ones are missing.
    func setWideSupported(_ supported: Bool) {
        lock.withLock { wideSupported = supported }
    }

    func setTimesOut(_ value: Bool) {
        lock.withLock { timesOut = value }
    }

    /// The reply to one encoded request, or a timeout when the router is set to be silent.
    func answer(_ request: [UInt8]) throws -> [UInt8] {
        if lock.withLock({ timesOut }) { throw SnmpError.timeout }
        let fields = try requestFields(request)
        let table = snapshotTable().sorted { $0.oid.arcs.lexicographicallyPrecedes($1.oid.arcs) }
        let bindings = fields.oids.map { oid -> [UInt8] in
            if fields.pduTag == BerTag.getNextRequest {
                return nextBinding(after: oid, in: table)
            }
            return exactBinding(oid, in: table)
        }
        return response(requestId: fields.requestId, bindings: bindings)
    }

    /// Every object the router has, encoded: counters in the kind it supports, the other kind as noSuchInstance, and the names.
    private func snapshotTable() -> [(oid: SnmpOid, value: [UInt8])] {
        lock.withLock {
            var entries: [(oid: SnmpOid, value: [UInt8])] = []
            for (index, pair) in counters {
                entries += counterEntries(index: index, pair: pair)
            }
            for (index, name) in names {
                guard let oid = OfficeRules.instance(OfficeRules.ifDescr, index: index) else { continue }
                entries.append((oid, BerWriter.octets(Array(name.utf8))))
            }
            return entries
        }
    }

    private func counterEntries(index: Int, pair: (inBytes: UInt64, outBytes: UInt64)) -> [(oid: SnmpOid, value: [UInt8])] {
        let wideValues = [(OfficeRules.ifHCInOctets, pair.inBytes), (OfficeRules.ifHCOutOctets, pair.outBytes)]
        let narrowValues = [(OfficeRules.ifInOctets, pair.inBytes), (OfficeRules.ifOutOctets, pair.outBytes)]
        let wideEntries = wideValues.compactMap { base, value in
            OfficeRules.instance(base, index: index).map { ($0, wideSupported ? counter64(value) : noSuch()) }
        }
        let narrowEntries = narrowValues.compactMap { base, value in
            OfficeRules.instance(base, index: index).map { ($0, wideSupported ? noSuch() : counter32(value)) }
        }
        return (wideEntries + narrowEntries).map { (oid: $0.0, value: $0.1) }
    }

    private func exactBinding(_ oid: SnmpOid, in table: [(oid: SnmpOid, value: [UInt8])]) -> [UInt8] {
        let value = table.first { $0.oid == oid }?.value ?? noSuch()
        return BerWriter.element(BerTag.sequence, BerWriter.oid(oid) + value)
    }

    private func nextBinding(after cursor: SnmpOid, in table: [(oid: SnmpOid, value: [UInt8])]) -> [UInt8] {
        guard let next = table.first(where: { cursor.arcs.lexicographicallyPrecedes($0.oid.arcs) }) else {
            return BerWriter.element(BerTag.sequence, BerWriter.oid(cursor) + BerWriter.element(BerTag.endOfMibView, []))
        }
        return BerWriter.element(BerTag.sequence, BerWriter.oid(next.oid) + next.value)
    }

    private func counter64(_ value: UInt64) -> [UInt8] {
        BerWriter.element(BerTag.counter64, unsignedContents(value))
    }

    /// A 32-bit counter keeps only its low 32 bits, as a real agent would.
    private func counter32(_ value: UInt64) -> [UInt8] {
        BerWriter.element(BerTag.counter32, unsignedContents(value & 0xFFFF_FFFF))
    }

    private func noSuch() -> [UInt8] {
        BerWriter.element(BerTag.noSuchInstance, [])
    }

    /// The minimal big-endian bytes of an unsigned number, with a leading zero when the top bit is set.
    private func unsignedContents(_ value: UInt64) -> [UInt8] {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
        while bytes.count > 1, bytes[0] == 0, bytes[1] & 0x80 == 0 { bytes.removeFirst() }
        return bytes[0] & 0x80 != 0 ? [0] + bytes : bytes
    }

    private func response(requestId: Int32, bindings: [[UInt8]]) -> [UInt8] {
        let variables = BerWriter.element(BerTag.sequence, bindings.flatMap { $0 })
        let pduContents = BerWriter.integer(Int64(requestId)) + BerWriter.integer(0) + BerWriter.integer(0) + variables
        let pdu = BerWriter.element(BerTag.getResponse, pduContents)
        let message = BerWriter.integer(1) + BerWriter.octets(Array("public".utf8)) + pdu
        return BerWriter.element(BerTag.sequence, message)
    }
}

/// The transport that hands every request to the fake router. Its timeout and its answers are the router's.
struct FakeOfficeTransport: SnmpTransport {
    let router: FakeOfficeRouter

    func exchange(_ request: [UInt8], timeout: TimeInterval) async throws -> [UInt8] {
        try router.answer(request)
    }
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
