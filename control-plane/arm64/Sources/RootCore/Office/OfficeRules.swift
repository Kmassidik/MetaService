import Foundation

/// The fixed numbers and OIDs of office bandwidth: the router's interface counters, how often they are read, how long minutes are kept and what counts as impossible.
public enum OfficeRules {
    /// Minutes older than this many days are deleted.
    public static let keepDays = 30
    /// The counters are read this often unless the owner sets another interval.
    public static let defaultIntervalSeconds = 60
    /// The owner may pick any interval from this many seconds up to the maximum.
    public static let minIntervalSeconds = 10
    public static let maxIntervalSeconds = 600
    /// The open minute is written this often, so a restart loses at most one minute.
    public static let flushSeconds = 60
    /// Interface names are read this often.
    public static let walkSeconds = 3_600
    /// Old minutes are deleted this often.
    public static let pruneSeconds = 3_600
    /// Most WAN indexes the owner may list.
    public static let maxWanIndexes = 8
    /// Most interface names read in one walk.
    public static let maxWalkEntries = 64
    /// A reading older than this many intervals is too far back to turn into one speed sample.
    public static let maxGapIntervals = 3
    /// A 32-bit counter starts again from zero after this many bytes.
    public static let counter32Modulus: UInt64 = 1 << 32
    /// Any single jump bigger than 40 gigabits in one interval is a glitch, not traffic.
    public static let maxBitsPerInterval: UInt64 = 40_000_000_000
    public static let bitsPerByte: UInt64 = 8
    public static let secondsPerMinute = NetUsageRules.secondsPerMinute

    /// ifHCInOctets: bytes received by an interface (64-bit), followed by the interface index.
    public static let ifHCInOctets: [UInt32] = [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 6]
    /// ifHCOutOctets: bytes sent by an interface (64-bit), followed by the interface index.
    public static let ifHCOutOctets: [UInt32] = [1, 3, 6, 1, 2, 1, 31, 1, 1, 1, 10]
    /// ifInOctets: bytes received by an interface (32-bit), followed by the interface index.
    public static let ifInOctets: [UInt32] = [1, 3, 6, 1, 2, 1, 2, 2, 1, 10]
    /// ifOutOctets: bytes sent by an interface (32-bit), followed by the interface index.
    public static let ifOutOctets: [UInt32] = [1, 3, 6, 1, 2, 1, 2, 2, 1, 16]
    /// ifDescr: the name of an interface, followed by the interface index.
    public static let ifDescr: [UInt32] = [1, 3, 6, 1, 2, 1, 2, 2, 1, 2]

    /// The OID of one interface's object: the base followed by the index. Nil only when the index is out of range for an OID.
    public static func instance(_ base: [UInt32], index: Int) -> SnmpOid? {
        guard let arc = UInt32(exactly: index) else { return nil }
        return SnmpOid(arcs: base + [arc])
    }

    /// The largest number of bytes one interval may count: the bit limit divided by eight.
    static var maxBytesPerInterval: UInt64 { maxBitsPerInterval / bitsPerByte }
}

/// One reading of an interface counter. A 64-bit counter (`wide`) and a 32-bit one are never compared with each other.
public struct OfficeCounter: Equatable, Sendable {
    public let value: UInt64
    public let wide: Bool

    public init(value: UInt64, wide: Bool) {
        self.value = value
        self.wide = wide
    }
}

/// The in and out counters of one WAN interface, read together.
public struct OfficeCounterPair: Equatable, Sendable {
    public let inCounter: OfficeCounter
    public let outCounter: OfficeCounter

    public init(inCounter: OfficeCounter, outCounter: OfficeCounter) {
        self.inCounter = inCounter
        self.outCounter = outCounter
    }
}

/// The bytes one interval moved in each direction.
public struct OfficeTraffic: Equatable, Sendable {
    public let inBytes: UInt64
    public let outBytes: UInt64

    public init(inBytes: UInt64, outBytes: UInt64) {
        self.inBytes = inBytes
        self.outBytes = outBytes
    }
}

/// Turns two counter readings into the bytes that moved between them.
public enum OfficeDelta {
    /// The bytes between `previous` and `now`. Nil when there is no earlier reading, the counter kinds differ, a 64-bit counter went down (a reset),
    /// or the jump is bigger than one interval can carry. A 32-bit counter that went down has wrapped once, so 2^32 is added back.
    public static func bytes(previous: OfficeCounter?, now: OfficeCounter) -> UInt64? {
        guard let previous, previous.wide == now.wide else { return nil }
        guard now.value < previous.value else { return plausible(now.value - previous.value) }
        guard !now.wide else { return nil }
        return plausible(OfficeRules.counter32Modulus - previous.value + now.value)
    }

    /// The count itself when one interval could carry it, otherwise nil.
    private static func plausible(_ bytes: UInt64) -> UInt64? {
        bytes <= OfficeRules.maxBytesPerInterval ? bytes : nil
    }
}

/// One minute of one WAN interface: the bytes in and out, the fastest speed of each direction in bytes per second, and how many readings were counted.
/// A minute can be written in parts, so the store adds the parts together.
public struct OfficeMinute: Equatable, Sendable {
    public let wanIndex: Int
    /// Epoch seconds divided by 60: the minute this traffic belongs to.
    public let minute: Int
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double
    public let samples: Int

    public init(wanIndex: Int, minute: Int, inBytes: Double, outBytes: Double, inPeakBps: Double, outPeakBps: Double, samples: Int) {
        self.wanIndex = wanIndex
        self.minute = minute
        self.inBytes = inBytes
        self.outBytes = outBytes
        self.inPeakBps = inPeakBps
        self.outPeakBps = outPeakBps
        self.samples = samples
    }

    /// A minute with nothing counted yet.
    static func empty(wanIndex: Int, minute: Int) -> OfficeMinute {
        OfficeMinute(wanIndex: wanIndex, minute: minute, inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0, samples: 0)
    }

    /// The minute with one more interval added. Its speed is the bytes divided by the seconds the interval covered.
    func adding(inBytes addedIn: Double, outBytes addedOut: Double, seconds: Double) -> OfficeMinute {
        OfficeMinute(wanIndex: wanIndex, minute: minute, inBytes: inBytes + addedIn, outBytes: outBytes + addedOut,
                     inPeakBps: max(inPeakBps, addedIn / seconds), outPeakBps: max(outPeakBps, addedOut / seconds), samples: samples + 1)
    }
}

/// Turns the counted intervals of each WAN interface into per-minute usage, one open minute per interface.
/// An interval not newer than the last one of its interface is ignored, so the same reading is never counted twice.
/// A minute is finished when a later minute of the same interface arrives; `takeOpenMinutes` hands over the minutes still being built.
public struct OfficeMinuteAccumulator: Sendable {
    private var open: [Int: OfficeMinute] = [:]
    private var lastSecond: [Int: Int] = [:]

    public init() {}

    /// Adds one interval that ended at `second` (epoch seconds) and lasted `seconds`. Returns the minute it finished, if any.
    public mutating func add(wanIndex: Int, at second: Int, inBytes: UInt64, outBytes: UInt64, seconds: Int) -> [OfficeMinute] {
        guard seconds > 0, isNewer(second, than: lastSecond[wanIndex]) else { return [] }
        lastSecond[wanIndex] = second
        let minute = second / OfficeRules.secondsPerMinute
        let finished = takeFinished(wanIndex, before: minute)
        let current = open[wanIndex] ?? .empty(wanIndex: wanIndex, minute: minute)
        open[wanIndex] = current.adding(inBytes: Double(inBytes), outBytes: Double(outBytes), seconds: Double(seconds))
        return finished
    }

    /// Hands over every minute still being built and starts them again empty. A later interval in the same minute makes a new part of it.
    public mutating func takeOpenMinutes() -> [OfficeMinute] {
        let minutes = Array(open.values)
        open.removeAll()
        return minutes
    }

    private func isNewer(_ second: Int, than last: Int?) -> Bool {
        last.map { second > $0 } ?? true
    }

    /// The interface's open minute, when the interval is in a later minute than it. That minute is removed and returned.
    private mutating func takeFinished(_ wanIndex: Int, before minute: Int) -> [OfficeMinute] {
        guard let current = open[wanIndex], current.minute < minute else { return [] }
        open[wanIndex] = nil
        return [current]
    }
}
