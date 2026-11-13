import XCTest
@testable import RootCore

final class PrimaryNetworkParseTests: XCTestCase {
    private func answer(network: String) -> Data {
        Data("""
        {"taken_at":"2026-11-14T10:00:00Z","measuring":false,"uptime_seconds":5,
         "cpu":{"core_count":2,"total_percent":1.5,"cores_percent":[1.0,2.0],"load":{"one":1.0,"five":1.0,"fifteen":1.0}},
         "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
         "disks":[],
         "network":\(network),
         "processes":[]}
        """.utf8)
    }

    private func network(_ extra: String) -> String {
        "{\"received_total_bytes\":1,\"sent_total_bytes\":2,\"received_bytes_per_second\":10,\"sent_bytes_per_second\":20\(extra)}"
    }

    func testPrimaryNetworkJsonWithoutTheNewKeysDecodesWithAllThreeNil() throws {
        let stats = try MachineStats.parse(answer(network: network("")))
        XCTAssertNil(stats.network.primaryInterface)
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
        XCTAssertEqual(stats.network.receivedBytesPerSecond, 10)
    }

    func testPrimaryNetworkJsonWithTheNewKeysDecodesRight() throws {
        let extra = ",\"primary_interface\":\"en0\",\"primary_received_bytes_per_second\":1234.5,\"primary_sent_bytes_per_second\":67"
        let stats = try MachineStats.parse(answer(network: network(extra)))
        XCTAssertEqual(stats.network.primaryInterface, "en0")
        XCTAssertEqual(stats.network.primaryReceivedBytesPerSecond, 1234.5)
        XCTAssertEqual(stats.network.primarySentBytesPerSecond, 67)
    }

    func testPrimaryNetworkNullValuesAreNil() throws {
        let extra = ",\"primary_interface\":null,\"primary_received_bytes_per_second\":null,\"primary_sent_bytes_per_second\":null"
        let stats = try MachineStats.parse(answer(network: network(extra)))
        XCTAssertNil(stats.network.primaryInterface)
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
    }

    func testPrimaryNetworkWrongTypesNegativeAndHostileValuesBecomeNil() throws {
        let extra = ",\"primary_interface\":42,\"primary_received_bytes_per_second\":\"NaN\",\"primary_sent_bytes_per_second\":-5"
        let stats = try MachineStats.parse(answer(network: network(extra)))
        XCTAssertNil(stats.network.primaryInterface)
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
        XCTAssertEqual(stats.network.sentBytesPerSecond, 20, "the rest of the answer is still read")
    }

    func testPrimaryNetworkAHostileInterfaceNameBecomesNil() throws {
        let extra = ",\"primary_interface\":\"en0; rm -rf /\""
        XCTAssertNil(try MachineStats.parse(answer(network: network(extra))).network.primaryInterface)
    }

    func testPrimaryNetworkAnInterfaceNameIsCutAtThirtyTwoCharacters() {
        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(MachineStats.interfaceName(long)?.count, MachineStats.maxInterfaceCharacters)
        XCTAssertEqual(MachineStats.interfaceName("bridge100.1_x-y"), "bridge100.1_x-y")
    }

    func testPrimaryNetworkEmptyAndNonAsciiInterfaceNamesBecomeNil() {
        XCTAssertNil(MachineStats.interfaceName(nil))
        XCTAssertNil(MachineStats.interfaceName(""))
        XCTAssertNil(MachineStats.interfaceName("en\u{0301}0"))
        XCTAssertNil(MachineStats.interfaceName("énp3s0"))
    }

    func testPrimaryNetworkNonFiniteAndNegativeSpeedsBecomeNil() {
        XCTAssertNil(MachineStats.rateOrNil(.nan))
        XCTAssertNil(MachineStats.rateOrNil(.infinity))
        XCTAssertNil(MachineStats.rateOrNil(-1))
        XCTAssertEqual(MachineStats.rateOrNil(0), 0)
    }
}

final class PrimaryNetworkHistoryTests: XCTestCase {
    private func stats(primary received: Double?, _ sent: Double?) -> MachineStats {
        MachineStats(takenAt: "2026-11-14T10:00:00Z", measuring: false, uptimeSeconds: 1,
                     cpu: .init(coreCount: 2, totalPercent: 10, coresPercent: nil, load: .init(one: 1, five: 2, fifteen: 3)),
                     memory: .init(totalBytes: 100, usedBytes: 40, cachedBytes: 20, freeBytes: 40, swapTotalBytes: 10, swapUsedBytes: 1), disks: [],
                     network: .init(receivedTotalBytes: 1, sentTotalBytes: 2, receivedBytesPerSecond: 300, sentBytesPerSecond: 400,
                                    primaryReceivedBytesPerSecond: received, primarySentBytesPerSecond: sent),
                     processes: [])
    }

    private func point(_ reading: MachineStats) -> HistoryPoint {
        HistoryPoint(stats: reading, at: Date(timeIntervalSince1970: 1_800_000_000))!
    }

    func testPrimaryNetworkHistoryUsesThePrimarySpeedsWhenBothArePresent() {
        let made = point(stats(primary: 7, 8))
        XCTAssertEqual([made.netInBps, made.netOutBps], [7, 8])
    }

    func testPrimaryNetworkHistoryFallsBackToTheTotalsWhenOnlyOneOrNoneIsPresent() {
        XCTAssertEqual([point(stats(primary: 7, nil)).netInBps, point(stats(primary: 7, nil)).netOutBps], [300, 400])
        XCTAssertEqual([point(stats(primary: nil, 8)).netInBps, point(stats(primary: nil, 8)).netOutBps], [300, 400])
        XCTAssertEqual([point(stats(primary: nil, nil)).netInBps, point(stats(primary: nil, nil)).netOutBps], [300, 400])
    }
}
