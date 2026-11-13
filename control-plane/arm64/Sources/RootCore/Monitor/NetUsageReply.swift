import Foundation

/// The traffic of one machine, or of several added together, over a window: the bytes in and out and the fastest speed of each direction.
public struct NetUsageFigures: Equatable, Sendable {
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(inBytes: Double, outBytes: Double, inPeakBps: Double, outPeakBps: Double) {
        self.inBytes = inBytes
        self.outBytes = outBytes
        self.inPeakBps = inPeakBps
        self.outPeakBps = outPeakBps
    }
}

/// One local day of traffic over all machines. `dayStart` is epoch seconds of the local midnight that starts the day.
public struct NetUsageDay: Equatable, Sendable, Encodable {
    public let dayStart: Int
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(dayStart: Int, inBytes: Double, outBytes: Double, inPeakBps: Double, outPeakBps: Double) {
        self.dayStart = dayStart
        self.inBytes = inBytes
        self.outBytes = outBytes
        self.inPeakBps = inPeakBps
        self.outPeakBps = outPeakBps
    }
}

/// The usage of one registered machine in a range, with its name. A machine with no data has zeros.
public struct NetUsageMachine: Equatable, Sendable, Encodable {
    public let machineId: String
    public let name: String
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(machineId: String, name: String, figures: NetUsageFigures) {
        self.machineId = machineId
        self.name = name
        inBytes = figures.inBytes
        outBytes = figures.outBytes
        inPeakBps = figures.inPeakBps
        outPeakBps = figures.outPeakBps
    }
}

/// The bytes of several machines added together. Peaks are not added: a total has no single fastest speed.
public struct NetUsageSummary: Equatable, Sendable, Encodable {
    public let inBytes: Double
    public let outBytes: Double

    public init(inBytes: Double, outBytes: Double) {
        self.inBytes = inBytes
        self.outBytes = outBytes
    }

    /// Adds the bytes of every figure given. Empty input gives zeros.
    public static func summarize(_ figures: [NetUsageFigures]) -> NetUsageSummary {
        NetUsageSummary(inBytes: figures.reduce(0) { $0 + $1.inBytes }, outBytes: figures.reduce(0) { $0 + $1.outBytes })
    }
}

/// The answer of the usage route for one range.
public struct NetUsageReply: Equatable, Sendable, Encodable {
    public let range: String
    public let since: Int
    public let machines: [NetUsageMachine]
    public let total: NetUsageSummary

    public init(range: String, since: Int, machines: [NetUsageMachine], total: NetUsageSummary) {
        self.range = range
        self.since = since
        self.machines = machines
        self.total = total
    }
}

/// The answer of the daily usage route: one entry per local day, oldest first, summed over all machines.
public struct NetUsageDailyReply: Equatable, Sendable, Encodable {
    public let days: [NetUsageDay]

    public init(days: [NetUsageDay]) {
        self.days = days
    }
}
