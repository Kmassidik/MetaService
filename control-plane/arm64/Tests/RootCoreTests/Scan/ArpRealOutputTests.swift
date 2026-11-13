import XCTest
@testable import RootCore

/// Uses `arp -an` text copied from a real macOS machine, so the parser and the merge are checked against the real format.
final class ArpRealOutputTests: XCTestCase {
    private let subnet = Subnet(cidr: "192.168.0.0/24")!

    private let realOutput = """
    ? (192.168.0.0) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
    ? (192.168.0.1) at 60:15:6f:c9:d0:98 on en0 ifscope [ethernet]
    ? (192.168.0.2) at (incomplete) on en0 ifscope [ethernet]
    ? (192.168.0.3) at (incomplete) on en0 ifscope [ethernet]
    ? (192.168.0.10) at 1c:1d:d3:d9:4b:f9 on en0 ifscope [ethernet]
    ? (192.168.0.30) at 4c:bb:47:2b:20:ec on en0 ifscope [ethernet]
    ? (192.168.0.40) at 1c:f6:4c:5b:89:2b on en0 ifscope permanent [ethernet]
    ? (192.168.0.50) at a8:5e:45:57:1c:72 on en0 ifscope [ethernet]
    ? (192.168.0.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
    """

    func testParsesRealMacOsArpOutput() {
        let table = ArpTable.parse(realOutput)
        XCTAssertEqual(table["192.168.0.1"], "60:15:6F:C9:D0:98")
        XCTAssertEqual(table["192.168.0.10"], "1C:1D:D3:D9:4B:F9")
        XCTAssertEqual(table["192.168.0.30"], "4C:BB:47:2B:20:EC")
        XCTAssertEqual(table["192.168.0.40"], "1C:F6:4C:5B:89:2B")
        XCTAssertEqual(table["192.168.0.50"], "A8:5E:45:57:1C:72")
    }

    func testIncompleteArpLinesProduceNoEntry() {
        let table = ArpTable.parse(realOutput)
        XCTAssertNil(table["192.168.0.2"])
        XCTAssertNil(table["192.168.0.3"])
    }

    func testMergeKeepsArpOnlyComputersWhenNmapSawOnlyTheRouter() {
        let nmap = [NmapHost(ip: "192.168.0.1", mac: nil, vendor: nil, hostname: nil, agentPortOpen: false)]
        let found = ScanMerge.merge(router: [], nmap: nmap, arp: ArpTable.parse(realOutput), subnet: subnet)
        XCTAssertEqual(found.map(\.ip), ["192.168.0.1", "192.168.0.10", "192.168.0.30", "192.168.0.40", "192.168.0.50"])
        XCTAssertFalse(found.map(\.ip).contains("192.168.0.0"), "network address must not be a computer")
        XCTAssertFalse(found.map(\.ip).contains("192.168.0.255"), "broadcast address must not be a computer")
        XCTAssertNotNil(found.first { $0.ip == "192.168.0.10" }?.mac)
    }

    func testMergeWithEmptyArpAndOnlyTheRouterKeepsOneRow() {
        let nmap = [NmapHost(ip: "192.168.0.1", mac: nil, vendor: nil, hostname: nil, agentPortOpen: false)]
        let found = ScanMerge.merge(router: [], nmap: nmap, arp: [:], subnet: subnet)
        XCTAssertEqual(found.map(\.ip), ["192.168.0.1"])
    }
}
