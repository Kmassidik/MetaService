import Foundation
import RootCore

/// Reads the in and out counters of every WAN index. The normal case is one GET for all of them; an index whose 64-bit counters are missing is asked for its 32-bit ones,
/// and that choice is remembered for the index, so the second request only happens once.
final class OfficeCounterReader {
    /// Per index: true when its counters are 64-bit, false when 32-bit. An index never seen starts as 64-bit.
    private var wideByIndex: [Int: Bool] = [:]

    /// The counter pair of every index that answered. Throws when an index answers in neither kind, or the exchange itself fails.
    func read(_ indexes: [Int], using client: SnmpClient) async throws -> [Int: OfficeCounterPair] {
        let answered = try await fetch(indexes.map { ($0, wideByIndex[$0] ?? true) }, using: client)
        let unanswered = indexes.filter { answered[$0] == nil }
        guard !unanswered.isEmpty else { return answered }
        let fallback = try await fetch(unanswered.map { ($0, false) }, using: client)
        guard fallback.count == unanswered.count else {
            throw SnmpError.badResponse("counters missing for a WAN index")
        }
        unanswered.forEach { wideByIndex[$0] = false }
        return answered.merging(fallback) { $1 }
    }

    /// One GET for the in and out counters of the given indexes, each in the kind given. Only indexes whose both counters came back are returned.
    private func fetch(_ requests: [(index: Int, wide: Bool)], using client: SnmpClient) async throws -> [Int: OfficeCounterPair] {
        guard !requests.isEmpty else { return [:] }
        let oids = requests.flatMap { oidPair(for: $0.index, wide: $0.wide) }
        let varbinds = try await client.get(oids)
        let values = Dictionary(varbinds.map { ($0.oid, $0.value) }, uniquingKeysWith: { first, _ in first })
        return requests.reduce(into: [:]) { result, request in
            guard let pair = counterPair(for: request.index, wide: request.wide, values: values) else { return }
            result[request.index] = pair
        }
    }

    /// The in and out OIDs of one index, in 64-bit or 32-bit form. Nil entries cannot happen for an index that fits an OID; they are dropped.
    private func oidPair(for index: Int, wide: Bool) -> [SnmpOid] {
        let inBase = wide ? OfficeRules.ifHCInOctets : OfficeRules.ifInOctets
        let outBase = wide ? OfficeRules.ifHCOutOctets : OfficeRules.ifOutOctets
        return [OfficeRules.instance(inBase, index: index), OfficeRules.instance(outBase, index: index)].compactMap { $0 }
    }

    /// The pair for one index from the answers, or nil when either counter is missing or of the wrong kind.
    private func counterPair(for index: Int, wide: Bool, values: [SnmpOid: SnmpValue]) -> OfficeCounterPair? {
        guard let inOid = OfficeRules.instance(wide ? OfficeRules.ifHCInOctets : OfficeRules.ifInOctets, index: index),
              let outOid = OfficeRules.instance(wide ? OfficeRules.ifHCOutOctets : OfficeRules.ifOutOctets, index: index),
              let inCounter = counter(values[inOid], wide: wide), let outCounter = counter(values[outOid], wide: wide) else { return nil }
        return OfficeCounterPair(inCounter: inCounter, outCounter: outCounter)
    }

    /// A counter from one answer. Only the kind asked for is accepted; noSuchObject and noSuchInstance give nil.
    private func counter(_ value: SnmpValue?, wide: Bool) -> OfficeCounter? {
        switch value {
        case .counter64(let number)? where wide:
            return OfficeCounter(value: number, wide: true)
        case .unsigned32(let number)? where !wide:
            return OfficeCounter(value: UInt64(number), wide: false)
        default:
            return nil
        }
    }
}
