import Foundation
import MSCore
import RootCore
import RootStore

/// Serves the office bandwidth of the WAN interfaces from the stored minutes, and owns the sampler that reads the router and writes them.
/// Not configured, every reply is empty with configured false; nothing is read from the router.
final class OfficeBandwidthService: Sendable {
    private let settings: OfficeSnmpSettings
    private let store: OfficeMinuteStore
    private let clock: Clock
    let sampler: OfficeBandwidthSampler

    init(settings: OfficeSnmpSettings, store: OfficeMinuteStore, clock: Clock, makeClient: @escaping OfficeBandwidthSampler.ClientFactory = OfficeBandwidthSampler.udpClient) {
        self.settings = settings
        self.store = store
        self.clock = clock
        sampler = OfficeBandwidthSampler(settings: settings, store: store, clock: clock, makeClient: makeClient)
    }

    /// Starts the sampler's loop. The loop returns at once when the router is not configured.
    func start() {
        let sampler = self.sampler
        Task.detached { await sampler.run() }
    }

    /// The usage of every configured WAN interface for a range, the total of them, and the poller's status.
    func usageReply(range: NetUsageRange) async throws -> OfficeUsageReply {
        let now = Int(clock.now.timeIntervalSince1970)
        let since = range.start(now: now)
        let names = Dictionary(await sampler.interfaces().map { ($0.index, $0.name) }, uniquingKeysWith: { first, _ in first })
        let indexes = settings.target?.wanIndexes ?? []
        let wans = try indexes.map { index in
            OfficeWanUsage(index: index, name: names[index] ?? "", figures: try store.usage(wanIndex: index, since: since, until: now))
        }
        return OfficeUsageReply(configured: settings.target != nil, status: await sampler.status(), interfaces: await sampler.interfaces(),
                                range: range.rawValue, since: since, wans: wans, total: OfficeTotal(wans: wans.map(figures(of:))))
    }

    /// Traffic per local day over all WAN interfaces, for the last `days` days including today, oldest first.
    func dailyReply(days: NetUsageDays) throws -> OfficeDailyReply {
        let now = Int(clock.now.timeIntervalSince1970)
        let firstDay = NetUsageRange.today.start(now: now) - (days.rawValue - 1) * NetUsageRules.secondsPerDay
        let rows = try store.dailyTotals(sinceMinute: firstDay / OfficeRules.secondsPerMinute,
                                         untilMinute: now / OfficeRules.secondsPerMinute + 1,
                                         offsetMinutes: NetUsageRules.officeUtcOffsetMinutes)
        return OfficeDailyReply(days: rows)
    }

    /// The interface names from a live walk of the router. Empty, with configured false, when it is not configured.
    func interfacesReply() async throws -> OfficeInterfacesReply {
        guard settings.target != nil else { return OfficeInterfacesReply(configured: false, interfaces: []) }
        return OfficeInterfacesReply(configured: true, interfaces: try await sampler.liveInterfaces())
    }

    private func figures(of wan: OfficeWanUsage) -> NetUsageFigures {
        NetUsageFigures(inBytes: wan.inBytes, outBytes: wan.outBytes, inPeakBps: wan.inPeakBps, outPeakBps: wan.outPeakBps)
    }
}
