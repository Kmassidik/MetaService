import Foundation

/// The fixed numbers of network usage: how often a speed is read, how often minutes are flushed, how long they are kept, and the office clock the days are cut by.
public enum NetUsageRules {
    /// One speed reading stands for this many seconds of traffic (the history sampler reads every ten seconds).
    public static let sampleSeconds = 10
    public static let secondsPerMinute = 60
    public static let secondsPerDay = 86_400
    /// The minute still being built is written this often, so a restart loses at most one minute.
    public static let flushSeconds = 60
    /// Minutes older than this many days are deleted.
    public static let keepDays = 30
    /// The office is in Indonesia (UTC+7); days are cut at local midnight.
    public static let officeUtcOffsetMinutes = 420
}

/// One minute of one machine's network traffic: the bytes received and sent in it, the fastest speed of each direction, and how many readings were counted.
/// A minute can be written in parts (a flush, then the rest of it), so the store adds the parts together.
public struct NetMinute: Equatable, Sendable {
    public let machineId: String
    /// Epoch seconds divided by 60: the minute this traffic belongs to.
    public let minute: Int
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double
    public let samples: Int

    public init(machineId: String, minute: Int, inBytes: Double, outBytes: Double, inPeakBps: Double, outPeakBps: Double, samples: Int) {
        self.machineId = machineId
        self.minute = minute
        self.inBytes = inBytes
        self.outBytes = outBytes
        self.inPeakBps = inPeakBps
        self.outPeakBps = outPeakBps
        self.samples = samples
    }

    /// A minute with no traffic counted yet.
    static func empty(_ machineId: String, minute: Int) -> NetMinute {
        NetMinute(machineId: machineId, minute: minute, inBytes: 0, outBytes: 0, inPeakBps: 0, outPeakBps: 0, samples: 0)
    }

    /// The minute with one more reading added. A missing speed counts as zero bytes; a reading with no speed at all is not a sample.
    func adding(inBps: Double?, outBps: Double?) -> NetMinute {
        let inSpeed = inBps ?? 0
        let outSpeed = outBps ?? 0
        let hasReading = inBps != nil || outBps != nil
        return NetMinute(machineId: machineId, minute: minute,
                         inBytes: inBytes + inSpeed * Double(NetUsageRules.sampleSeconds),
                         outBytes: outBytes + outSpeed * Double(NetUsageRules.sampleSeconds),
                         inPeakBps: max(inPeakBps, inSpeed), outPeakBps: max(outPeakBps, outSpeed),
                         samples: samples + (hasReading ? 1 : 0))
    }
}

/// Turns the speed readings of the machines into per-minute usage, one minute open per machine at a time.
/// A reading not newer than the last reading of its machine is ignored, so the same reading is never counted twice.
/// A minute is finished when a later minute of the same machine arrives; `takeOpenMinutes` hands over the minutes still being built.
public struct NetMinuteAccumulator: Sendable {
    private var open: [String: NetMinute] = [:]
    private var lastSecond: [String: Int] = [:]

    public init() {}

    /// Adds one reading: its time in epoch seconds and the speeds in bytes per second (nil when unknown). Returns the minute it finished, if any.
    public mutating func add(machineId: String, at second: Int, inBps: Double?, outBps: Double?) -> [NetMinute] {
        guard isNewer(second, than: lastSecond[machineId]) else { return [] }
        lastSecond[machineId] = second
        let minute = second / NetUsageRules.secondsPerMinute
        let finished = takeFinished(machineId, before: minute)
        open[machineId] = (open[machineId] ?? .empty(machineId, minute: minute)).adding(inBps: inBps, outBps: outBps)
        return finished
    }

    /// Hands over every minute still being built and starts them again empty. A later reading in the same minute makes a new part of it.
    public mutating func takeOpenMinutes() -> [NetMinute] {
        let minutes = Array(open.values)
        open.removeAll()
        return minutes
    }

    private func isNewer(_ second: Int, than last: Int?) -> Bool {
        last.map { second > $0 } ?? true
    }

    /// The machine's open minute, when the reading is in a later minute than it. That minute is removed and returned.
    private mutating func takeFinished(_ machineId: String, before minute: Int) -> [NetMinute] {
        guard let current = open[machineId], current.minute < minute else { return [] }
        open[machineId] = nil
        return [current]
    }
}
