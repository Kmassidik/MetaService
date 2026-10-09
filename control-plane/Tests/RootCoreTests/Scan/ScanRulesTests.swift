import XCTest
@testable import RootCore

final class ScanRulesTests: XCTestCase {
    private let subnet = Subnet(cidr: "192.168.100.0/24")!

    // MARK: subnet and addresses

    func testSubnetAcceptsPrivateNetworksOnly() {
        XCTAssertTrue(subnet.isPrivate)
        for cidr in ["10.0.0.0/8", "172.16.0.0/12"] { XCTAssertNil(Subnet(cidr: cidr), "\(cidr) is wider than a /22") }
        XCTAssertTrue(Subnet(cidr: "10.1.0.0/22")!.isPrivate)
        XCTAssertTrue(Subnet(cidr: "172.20.4.0/24")!.isPrivate)
        XCTAssertFalse(Subnet(cidr: "8.8.8.0/24")!.isPrivate)
        XCTAssertFalse(Subnet(cidr: "172.32.0.0/24")!.isPrivate)
        XCTAssertFalse(Subnet(cidr: "192.169.0.0/24")!.isPrivate)
    }

    func testSubnetRefusesBadText() {
        for bad in ["", "192.168.100.0", "192.168.100.0/", "192.168.100.0/33", "192.168.100.0/21", "192.168.100.5/24", "300.1.1.0/24", "a.b.c.d/24",
                    "192.168.100.0/24; reboot", "192.168.100.0/ 24", "192.168.100/24", "-oN /tmp/x/24"] {
            XCTAssertNil(Subnet(cidr: bad), bad)
        }
    }

    func testContains() {
        XCTAssertTrue(subnet.contains("192.168.100.40"))
        XCTAssertTrue(subnet.contains("192.168.100.255"))
        for outside in ["192.168.101.1", "10.0.0.1", "", "192.168.100", "192.168.100.256", "192.168.100.1 ", "-iL"] { XCTAssertFalse(subnet.contains(outside), outside) }
        XCTAssertEqual(subnet.description, "192.168.100.0/24")
    }

    func testMacNormalizing() {
        XCTAssertEqual(MacAddress.normalize("a:1B:2c:3:4:5f"), "0A:1B:2C:03:04:5F")
        XCTAssertEqual(MacAddress.normalize("aa-bb-cc-dd-ee-ff"), "AA:BB:CC:DD:EE:FF")
        for bad in ["", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "zz:bb:cc:dd:ee:ff", "00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "(incomplete)", "aaa:bb:cc:dd:ee:ff"] {
            XCTAssertNil(MacAddress.normalize(bad), bad)
        }
    }

    // MARK: parsing

    func testNmapXmlReadsLiveHostsOnly() {
        let xml = """
        <?xml version="1.0"?><nmaprun><host><status state="up"/><address addr="192.168.100.1" addrtype="ipv4"/>
        <address addr="AA:BB:CC:DD:EE:01" addrtype="mac" vendor="MikroTik"/><hostnames><hostname name="router.lan" type="PTR"/><hostname name="other" type="user"/></hostnames>
        <ports><port protocol="tcp" portid="9101"><state state="open"/></port></ports></host>
        <host><status state="down"/><address addr="192.168.100.9" addrtype="ipv4"/></host>
        <host><status state="up"/><address addr="192.168.100.40" addrtype="ipv4"/><ports><port protocol="tcp" portid="9101"><state state="closed"/></port></ports></host>
        <host><status state="up"/><address addr="not-an-ip" addrtype="ipv4"/></host></nmaprun>
        """
        let hosts = NmapXml.hosts(from: Data(xml.utf8), agentPort: 9101)
        XCTAssertEqual(hosts.map(\.ip), ["192.168.100.1", "192.168.100.40"])
        XCTAssertEqual(hosts[0], NmapHost(ip: "192.168.100.1", mac: "AA:BB:CC:DD:EE:01", vendor: "MikroTik", hostname: "router.lan", agentPortOpen: true))
        XCTAssertFalse(hosts[1].agentPortOpen)
        XCTAssertNil(hosts[1].mac)
    }

    func testNmapXmlSurvivesGarbageAndEntityBombs() {
        XCTAssertTrue(NmapXml.hosts(from: Data("not xml".utf8), agentPort: nil).isEmpty)
        XCTAssertTrue(NmapXml.hosts(from: Data(), agentPort: nil).isEmpty)
        let bomb = """
        <?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;"><!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>
        <nmaprun><host><status state="up"/><address addr="192.168.100.7" addrtype="ipv4"/><hostnames><hostname name="&c;"/></hostnames></host></nmaprun>
        """
        let started = Date()
        _ = NmapXml.hosts(from: Data(bomb.utf8), agentPort: nil)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testArpTableReadsMacAndLinuxLines() {
        let output = """
        ? (192.168.100.1) at a:b:c:d:e:f on en0 ifscope [ethernet]
        ? (192.168.100.40) at 0:1a:2b:3c:4d:5e on en0 ifscope permanent [ethernet]
        ? (192.168.100.77) at (incomplete) on en0 ifscope [ethernet]
        router.lan (192.168.100.2) at aa:bb:cc:dd:ee:02 [ether] on eth0
        ? (999.1.1.1) at aa:bb:cc:dd:ee:03 on en0
        garbage line
        """
        let table = ArpTable.parse(output)
        XCTAssertEqual(table["192.168.100.1"], "0A:0B:0C:0D:0E:0F")
        XCTAssertEqual(table["192.168.100.40"], "00:1A:2B:3C:4D:5E")
        XCTAssertEqual(table["192.168.100.2"], "AA:BB:CC:DD:EE:02")
        XCTAssertNil(table["192.168.100.77"])
        XCTAssertNil(table["999.1.1.1"])
    }

    func testRouterOsLeasesAndArp() {
        let leases = Data("""
        [{".id":"*1","address":"192.168.100.40","mac-address":"AA:BB:CC:00:00:40","host-name":"macbook","status":"bound","disabled":"false"},
         {".id":"*2","address":"192.168.100.41","mac-address":"AA:BB:CC:00:00:41","status":"waiting"},
         {".id":"*3","address":"192.168.100.42","mac-address":"AA:BB:CC:00:00:42","disabled":"true"},
         {".id":"*4","address":"not-an-ip","mac-address":"AA:BB:CC:00:00:43","status":"bound"},
         {".id":"*5","address":"192.168.100.44","mac-address":"AA:BB:CC:00:00:44","comment":"office printer","status":"bound"}]
        """.utf8)
        XCTAssertEqual(RouterOSRest.leases(from: leases), [
            RouterEntry(ip: "192.168.100.40", mac: "AA:BB:CC:00:00:40", hostname: "macbook"),
            RouterEntry(ip: "192.168.100.44", mac: "AA:BB:CC:00:00:44", hostname: "office printer"),
        ])
        let arp = Data(#"[{"address":"192.168.100.1","mac-address":"AA:BB:CC:00:00:01","complete":"true"},{"address":"192.168.100.9","complete":"false"}]"#.utf8)
        XCTAssertEqual(RouterOSRest.arp(from: arp), [RouterEntry(ip: "192.168.100.1", mac: "AA:BB:CC:00:00:01", hostname: nil)])
        for junk in ["", "{}", "null", "[1,2]", "{\"error\":401}"] { XCTAssertTrue(RouterOSRest.leases(from: Data(junk.utf8)).isEmpty, junk) }
    }

    // MARK: merging

    func testMergeJoinsSourcesAndKeepsTheFirstNonEmptyValues() {
        let router = [RouterEntry(ip: "192.168.100.40", mac: "AA:BB:CC:00:00:40", hostname: "macbook"), RouterEntry(ip: "192.168.100.50", mac: "AA:BB:CC:00:00:50", hostname: nil)]
        let nmap = [NmapHost(ip: "192.168.100.40", mac: nil, vendor: nil, hostname: "ignored.lan"), NmapHost(ip: "192.168.100.60", mac: nil, vendor: nil, hostname: nil, agentPortOpen: true)]
        let found = ScanMerge.merge(router: router, nmap: nmap, arp: ["192.168.100.60": "AA:BB:CC:00:00:60", "192.168.100.99": "AA:BB:CC:00:00:99"], subnet: subnet)
        XCTAssertEqual(found.map(\.ip), ["192.168.100.40", "192.168.100.50", "192.168.100.60"])
        XCTAssertEqual(found[0].hostname, "macbook")
        XCTAssertEqual(found[0].seenBy, [.router, .nmap])
        XCTAssertEqual(found[1].seenBy, [.router])
        XCTAssertEqual(found[2].mac, "AA:BB:CC:00:00:60")
        XCTAssertTrue(found[2].agentPortOpen)
        XCTAssertEqual(found[2].seenBy, [.nmap, .arp])
    }

    func testMergeIgnoresAddressesOutsideTheSubnet() {
        let found = ScanMerge.merge(router: [RouterEntry(ip: "10.0.0.5", mac: nil, hostname: nil)], nmap: [NmapHost(ip: "8.8.8.8", mac: nil, vendor: nil, hostname: nil)], arp: [:], subnet: subnet)
        XCTAssertTrue(found.isEmpty)
    }

    func testMergeKeepsTheLiveAddressWhenOneMacHasTwo() {
        let router = [RouterEntry(ip: "192.168.100.70", mac: "AA:BB:CC:00:00:70", hostname: "old-lease")]
        let nmap = [NmapHost(ip: "192.168.100.71", mac: "AA:BB:CC:00:00:70", vendor: nil, hostname: nil)]
        let found = ScanMerge.merge(router: router, nmap: nmap, arp: [:], subnet: subnet)
        XCTAssertEqual(found.map(\.ip), ["192.168.100.71"])
    }

    func testMergeCleansHostileNames() {
        let name = "evil\u{0000}\u{001B}[31m<script>" + String(repeating: "x", count: 500)
        let found = ScanMerge.merge(router: [RouterEntry(ip: "192.168.100.5", mac: nil, hostname: name)], nmap: [], arp: [:], subnet: subnet)
        XCTAssertLessThanOrEqual(found[0].hostname?.count ?? 0, 100)
        XCTAssertFalse(found[0].hostname?.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) ?? true)
        let blank = ScanMerge.merge(router: [RouterEntry(ip: "192.168.100.6", mac: nil, hostname: "   ")], nmap: [], arp: [:], subnet: subnet)
        XCTAssertNil(blank[0].hostname)
    }
}
