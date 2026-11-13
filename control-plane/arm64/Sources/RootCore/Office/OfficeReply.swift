import Foundation

/// Whether the router's counters can be read. The raw values are what the JSON answer carries.
public enum OfficeState: String, Equatable, Sendable, Encodable {
    case notConfigured = "not_configured"
    case ok
    case failed
}

/// The state of the poller with a fixed text that says it in plain words, plus the time of the last good reading (epoch seconds).
public struct OfficeStatus: Equatable, Sendable {
    public let state: OfficeState
    public let detail: String
    public let lastOkAt: Int?

    public init(state: OfficeState, detail: String, lastOkAt: Int?) {
        self.state = state
        self.detail = detail
        self.lastOkAt = lastOkAt
    }

    /// Before the first poll of a configured router.
    public static let waiting = OfficeStatus(state: .failed, detail: OfficeFailure.waitingPhrase, lastOkAt: nil)
    /// When the owner has not set the router up.
    public static let notConfigured = OfficeStatus(state: .notConfigured, detail: OfficeFailure.notConfiguredPhrase, lastOkAt: nil)
}

/// The fixed texts that describe the poller. The router's own error text is never shown, so nothing from it can leak.
public enum OfficeFailure {
    public static let waitingPhrase = "Waiting for the first reading"
    public static let notConfiguredPhrase = "SNMP is not configured"
    public static let okPhrase = "The router answered"
    public static let timeoutPhrase = "The router did not answer (check SNMP and the community)"
    public static let refusedPhrase = "The router refused the request"
    public static let unexpectedPhrase = "Unexpected answer from the router"

    /// The fixed text for a failed exchange: a timeout, an SNMP error status, or anything else.
    public static func phrase(for error: Error) -> String {
        switch error as? SnmpError {
        case .timeout?:
            return timeoutPhrase
        case .agentError?:
            return refusedPhrase
        default:
            return unexpectedPhrase
        }
    }
}

/// One WAN interface name from the last walk of the router's interface table.
public struct OfficeInterface: Equatable, Sendable, Encodable {
    public let index: Int
    public let name: String

    public init(index: Int, name: String) {
        self.index = index
        self.name = name
    }
}

/// The traffic of one WAN interface over a window. `name` is empty when no walk has named it yet.
public struct OfficeWanUsage: Equatable, Sendable, Encodable {
    public let index: Int
    public let name: String
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(index: Int, name: String, figures: NetUsageFigures) {
        self.index = index
        self.name = name
        inBytes = figures.inBytes
        outBytes = figures.outBytes
        inPeakBps = figures.inPeakBps
        outPeakBps = figures.outPeakBps
    }
}

/// All WAN interfaces added together. The peak is the sum of each WAN's own peak; the fastest sum in one minute is not tracked, so this is an upper bound.
public struct OfficeTotal: Equatable, Sendable, Encodable {
    public let inBytes: Double
    public let outBytes: Double
    public let inPeakBps: Double
    public let outPeakBps: Double

    public init(wans: [NetUsageFigures]) {
        inBytes = wans.reduce(0) { $0 + $1.inBytes }
        outBytes = wans.reduce(0) { $0 + $1.outBytes }
        inPeakBps = wans.reduce(0) { $0 + $1.inPeakBps }
        outPeakBps = wans.reduce(0) { $0 + $1.outPeakBps }
    }
}

/// The answer of the usage route for one range: the poller's status, each configured WAN and the total.
public struct OfficeUsageReply: Equatable, Sendable, Encodable {
    public let configured: Bool
    public let state: OfficeState
    public let detail: String
    public let lastOkAt: Int?
    public let interfaces: [OfficeInterface]
    public let range: String
    public let since: Int
    public let wans: [OfficeWanUsage]
    public let total: OfficeTotal

    public init(configured: Bool, status: OfficeStatus, interfaces: [OfficeInterface], range: String, since: Int, wans: [OfficeWanUsage], total: OfficeTotal) {
        self.configured = configured
        state = status.state
        detail = status.detail
        lastOkAt = status.lastOkAt
        self.interfaces = interfaces
        self.range = range
        self.since = since
        self.wans = wans
        self.total = total
    }
}

/// The answer of the daily route: one entry per local day, oldest first, summed over all WAN interfaces.
public struct OfficeDailyReply: Equatable, Sendable, Encodable {
    public let days: [NetUsageDay]

    public init(days: [NetUsageDay]) {
        self.days = days
    }
}

/// The answer of the interfaces route: the names from a live walk. Empty, with configured false, when the router is not set up.
public struct OfficeInterfacesReply: Equatable, Sendable, Encodable {
    public let configured: Bool
    public let interfaces: [OfficeInterface]

    public init(configured: Bool, interfaces: [OfficeInterface]) {
        self.configured = configured
        self.interfaces = interfaces
    }
}
