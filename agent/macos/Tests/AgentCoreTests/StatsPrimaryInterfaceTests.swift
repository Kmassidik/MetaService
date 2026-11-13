import XCTest
@testable import AgentCore

private final class ListSource: StatsSource {
    var snapshots: [StatsSnapshot]
    init(_ snapshots: [StatsSnapshot]) { self.snapshots = snapshots }
    func read(includeProcesses: Bool) throws -> StatsSnapshot { snapshots.removeFirst() }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private let realRouteOutput = """
   route to: default
destination: default
       mask: default
    gateway: 192.168.0.1
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRIVATE>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
       0         0         0         0         0         0      1500         0
"""

private func counters(_ name: String?, received: UInt64 = 0, sent: UInt64 = 0) -> InterfaceCounters? {
    name.map { InterfaceCounters(name: $0, receivedBytes: received, sentBytes: sent) }
}

private func snapshot(at seconds: Double = 0, primary: InterfaceCounters?) -> StatsSnapshot {
    StatsSnapshot(takenAt: start.addingTimeInterval(seconds), uptimeSeconds: 1, cores: [CoreTicks(busy: 0, total: 0)], load: [nil, nil, nil],
                  memory: MemoryReading(totalBytes: 10, usedBytes: 5, cachedBytes: 3, freeBytes: 2, swapTotalBytes: 0, swapUsedBytes: 0), disks: [],
                  receivedTotalBytes: 0, sentTotalBytes: 0, processes: [], extras: StatsExtras(primaryInterface: primary))
}

private func twoAnswers(_ first: StatsSnapshot, _ second: StatsSnapshot) throws -> (MachineStats, MachineStats) {
    let sampler = StatsSampler(source: ListSource([first, second]))
    return (try sampler.sample(), try sampler.sample())
}

private func json(_ stats: MachineStats) throws -> String { String(decoding: try StatsJson.encode(stats), as: UTF8.self) }

final class StatsPrimaryInterfaceTests: XCTestCase {
    func testTheRealRouteOutputGivesEn0() {
        XCTAssertEqual(PrimaryInterface.parse(routeOutput: realRouteOutput), "en0")
    }

    func testNoInterfaceLineGivesNil() {
        XCTAssertNil(PrimaryInterface.parse(routeOutput: "   route to: default\n    gateway: 192.168.0.1\n"))
        XCTAssertNil(PrimaryInterface.parse(routeOutput: ""))
    }

    func testGarbageGivesNil() {
        XCTAssertNil(PrimaryInterface.parse(routeOutput: "route: writing to routing socket: not in table\n\u{0}\u{1}??"))
    }

    func testHostileNamesGiveNil() {
        let hostile = ["  interface: en0; rm -rf /", "interface: ../../etc", "interface: en0 en1", "interface: ", "interface:", "interface: en0$(id)", "interface: énö", "interface: en0`x`"]
        for line in hostile {
            XCTAssertNil(PrimaryInterface.parse(routeOutput: line), "\(line) must be refused")
        }
    }

    func testDotUnderscoreAndDashAreAllowedInTheName() {
        XCTAssertEqual(PrimaryInterface.parse(routeOutput: "  interface: bridge-1.2_x"), "bridge-1.2_x")
    }

    func testPrimarySpeedIsTheChangeOfTheNamedInterfaceOnly() throws {
        let first = snapshot(primary: counters("en0", received: 1000, sent: 0))
        let second = snapshot(at: 5, primary: counters("en0", received: 6000, sent: 500))
        let stats = try twoAnswers(first, second).1
        XCTAssertEqual(stats.network.primaryInterface, "en0")
        XCTAssertEqual(stats.network.primaryReceivedBytesPerSecond, 1000)
        XCTAssertEqual(stats.network.primarySentBytesPerSecond, 100)
    }

    func testPrimarySpeedIsNullWhileMeasuring() throws {
        let stats = try twoAnswers(snapshot(primary: counters("en0", received: 1000)), snapshot(at: 5, primary: counters("en0", received: 6000))).0
        XCTAssertEqual(stats.network.primaryInterface, "en0")
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
    }

    func testPrimarySpeedIsNullWhenTheNameChanged() throws {
        let first = snapshot(primary: counters("en0", received: 1000))
        let second = snapshot(at: 5, primary: counters("en1", received: 6000))
        let stats = try twoAnswers(first, second).1
        XCTAssertEqual(stats.network.primaryInterface, "en1")
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
    }

    func testPrimarySpeedIsNullWhenNoNameIsKnown() throws {
        let stats = try twoAnswers(snapshot(primary: nil), snapshot(at: 5, primary: nil)).1
        XCTAssertNil(stats.network.primaryInterface)
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertNil(stats.network.primarySentBytesPerSecond)
    }

    func testPrimaryCounterThatWentBackwardsIsNullNotNegative() throws {
        let first = snapshot(primary: counters("en0", received: 9000, sent: 10))
        let second = snapshot(at: 5, primary: counters("en0", received: 100, sent: 60))
        let stats = try twoAnswers(first, second).1
        XCTAssertNil(stats.network.primaryReceivedBytesPerSecond)
        XCTAssertEqual(stats.network.primarySentBytesPerSecond, 10)
    }

    func testJsonHasTheThreeNewKeysAndNullsWhileMeasuring() throws {
        let (measuring, ready) = try twoAnswers(snapshot(primary: counters("en0", received: 1000)), snapshot(at: 5, primary: counters("en0", received: 6000, sent: 500)))
        let measuringText = try json(measuring)
        XCTAssertTrue(measuringText.contains("\"primary_interface\":\"en0\""))
        XCTAssertTrue(measuringText.contains("\"primary_received_bytes_per_second\":null"))
        XCTAssertTrue(measuringText.contains("\"primary_sent_bytes_per_second\":null"))
        let readyText = try json(ready)
        XCTAssertTrue(readyText.contains("\"primary_received_bytes_per_second\":1000"))
        XCTAssertTrue(readyText.contains("\"primary_sent_bytes_per_second\":100"))
    }
}
