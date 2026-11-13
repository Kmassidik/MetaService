import XCTest
import MSCore
import RootCore
import RootStore
@testable import Root

private final class OfficeTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: Int) { lock.withLock { current = current.addingTimeInterval(TimeInterval(seconds)) } }
}

private final class OfficeClientCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func record() { lock.withLock { calls += 1 } }
    var count: Int { lock.withLock { calls } }
}

final class OfficeBandwidthSamplerTests: XCTestCase {
    private var router: FakeOfficeRouter!
    private var clock: OfficeTestClock!
    private var store: OfficeMinuteStore!
    private var clientCalls: OfficeClientCounter!

    override func setUpWithError() throws {
        router = FakeOfficeRouter()
        clock = OfficeTestClock()
        let database = try Database(path: ":memory:")
        try Migrations.migrate(database)
        store = OfficeMinuteStore(database)
        clientCalls = OfficeClientCounter()
        router.setCounters(index: 19, inBytes: 1_000, outBytes: 2_000)
        router.setCounters(index: 20, inBytes: 0, outBytes: 0)
        router.setNames([19: "WAN1", 20: "WAN2", 1: "LAN"])
    }

    private func configuredSettings() throws -> OfficeSnmpSettings {
        try OfficeSnmpSettings.parse([OfficeSnmpSettings.hostKey: "192.0.2.1", OfficeSnmpSettings.communityKey: "public",
                                      OfficeSnmpSettings.wanIndexesKey: "19,20", OfficeSnmpSettings.intervalKey: "60"])
    }

    private func makeSampler(settings: OfficeSnmpSettings? = nil) throws -> OfficeBandwidthSampler {
        let router = self.router!
        let counter = clientCalls!
        return OfficeBandwidthSampler(settings: try settings ?? configuredSettings(), store: store, clock: clock, makeClient: { _ in
            counter.record()
            return SnmpClient(transport: FakeOfficeTransport(router: router), community: "public")
        })
    }

    private func storedInBytes(_ wan: Int) throws -> Double {
        try store.usage(wanIndex: wan, since: 0, until: 2_000_000_000).inBytes
    }

    func testOfficeNotConfiguredNeverStartsOrCallsTheRouter() async throws {
        let sampler = try makeSampler(settings: try OfficeSnmpSettings.parse([:]))
        await sampler.run()
        await sampler.pollOnce()
        let status = await sampler.status()
        XCTAssertEqual(status.state, .notConfigured)
        XCTAssertEqual(clientCalls.count, 0)
    }

    func testOfficeGoodPollTwiceStoresOneDelta() async throws {
        let sampler = try makeSampler()
        await sampler.pollOnce()
        router.setCounters(index: 19, inBytes: 1_600, outBytes: 2_900)
        clock.advance(60)
        await sampler.pollOnce()
        await sampler.maintain()
        XCTAssertEqual(try storedInBytes(19), 600)
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 2_000_000_000).outBytes, 900)
        let status = await sampler.status()
        XCTAssertEqual(status.state, .ok)
        XCTAssertEqual(status.detail, OfficeFailure.okPhrase)
    }

    func testOfficeNamesComeFromTheWalk() async throws {
        let sampler = try makeSampler()
        await sampler.pollOnce()
        let names = await sampler.interfaces()
        XCTAssertEqual(names, [OfficeInterface(index: 1, name: "LAN"), OfficeInterface(index: 19, name: "WAN1"), OfficeInterface(index: 20, name: "WAN2")])
    }

    func testOfficeThirtyTwoBitCountersAreUsedWhenSixtyFourAreMissing() async throws {
        router.setWideSupported(false)
        router.setCounters(index: 19, inBytes: 4_294_967_000, outBytes: 100)
        let sampler = try makeSampler()
        await sampler.pollOnce()
        router.setCounters(index: 19, inBytes: 500, outBytes: 400)
        clock.advance(60)
        await sampler.pollOnce()
        await sampler.maintain()
        XCTAssertEqual(try storedInBytes(19), 796)
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 2_000_000_000).outBytes, 300)
        let status = await sampler.status()
        XCTAssertEqual(status.state, .ok)
    }

    func testOfficeTimeoutSetsFailedAndKeepsTheCounter() async throws {
        let sampler = try makeSampler()
        await sampler.pollOnce()
        router.setTimesOut(true)
        clock.advance(60)
        await sampler.pollOnce()
        let failed = await sampler.status()
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.detail, "The router did not answer (check SNMP and the community)")
        router.setTimesOut(false)
        router.setCounters(index: 19, inBytes: 1_300, outBytes: 2_500)
        clock.advance(60)
        await sampler.pollOnce()
        await sampler.maintain()
        XCTAssertEqual(try storedInBytes(19), 300)
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 2_000_000_000).outBytes, 500)
    }

    func testOfficeGapLongerThanThreeIntervalsDropsTheDelta() async throws {
        let sampler = try makeSampler()
        await sampler.pollOnce()
        clock.advance(4 * 60)
        router.setCounters(index: 19, inBytes: 2_000, outBytes: 2_000)
        await sampler.pollOnce()
        clock.advance(60)
        router.setCounters(index: 19, inBytes: 2_600, outBytes: 2_300)
        await sampler.pollOnce()
        await sampler.maintain()
        XCTAssertEqual(try storedInBytes(19), 600)
        XCTAssertEqual(try store.usage(wanIndex: 19, since: 0, until: 2_000_000_000).outBytes, 300)
    }
}
