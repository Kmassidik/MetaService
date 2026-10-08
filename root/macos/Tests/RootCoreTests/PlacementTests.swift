import XCTest
@testable import RootCore

final class PlacementTests: XCTestCase {
    private let vmOnly = Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false)
    private let everything = Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: true)

    private func machine(_ id: String, online: Bool = true, caps: Capabilities? = nil, ram: Int, disk: Int) -> PlacementMachine {
        PlacementMachine(id: id, online: online, capabilities: caps ?? everything, freeRamMb: ram, freeDiskGb: disk)
    }

    private func wish(kind: String = "vm", gpu: String = "none", ram: Int = 1024, disk: Int = 10, only: String? = nil) -> PlacementWish {
        PlacementWish(kind: kind, gpuMode: gpu, ramMb: ram, diskGb: disk, onlyMachine: only)
    }

    func testPicksTheMachineWithTheMostRoomLeft() throws {
        let pool = [machine("small", ram: 4096, disk: 100), machine("big", ram: 65536, disk: 100), machine("mid", ram: 16384, disk: 900)]
        XCTAssertEqual(try Placement.choose(pool, wish()), "big")
        XCTAssertEqual(try Placement.choose(pool, wish(only: "mid")), "mid")
    }

    func testTiesBreakOnDiskThenAreStable() throws {
        let pool = [machine("a", ram: 8192, disk: 100), machine("b", ram: 8192, disk: 500)]
        XCTAssertEqual(try Placement.choose(pool, wish()), "b")
    }

    func testOfflineMachinesAreNeverChosen() {
        XCTAssertThrowsError(try Placement.choose([machine("x", online: false, ram: 99999, disk: 9999)], wish())) { XCTAssertEqual(($0 as? PlacementRefusal)?.code, "no_machine_online") }
        XCTAssertThrowsError(try Placement.choose([], wish())) { XCTAssertEqual(($0 as? PlacementRefusal)?.code, "machine_not_found") }
        XCTAssertThrowsError(try Placement.choose([machine("a", ram: 9999, disk: 99)], wish(only: "nope"))) { XCTAssertEqual(($0 as? PlacementRefusal)?.code, "machine_not_found") }
    }

    func testCapabilitiesDecide() throws {
        let pool = [machine("mac", caps: vmOnly, ram: 90000, disk: 900), machine("dgx", caps: everything, ram: 8000, disk: 900)]
        XCTAssertEqual(try Placement.choose(pool, wish(kind: "container")), "dgx", "the Mac cannot run containers even with more room")
        XCTAssertEqual(try Placement.choose(pool, wish(kind: "container", gpu: "container")), "dgx")
        for impossible in [wish(kind: "vm", gpu: "passthrough"), wish(kind: "vm", gpu: "container"), wish(kind: "container", gpu: "passthrough")] {
            XCTAssertThrowsError(try Placement.choose(pool, impossible)) { XCTAssertEqual(($0 as? PlacementRefusal)?.code, "missing_capability") }
        }
        XCTAssertThrowsError(try Placement.choose([PlacementMachine(id: "new", online: true, capabilities: nil, freeRamMb: 9999, freeDiskGb: 99)], wish()))
    }

    func testRefusalsCarryTheNumbersOfTheRoomiestMachine() {
        let pool = [machine("a", ram: 4096, disk: 50), machine("b", ram: 8192, disk: 20)]
        XCTAssertThrowsError(try Placement.choose(pool, wish(ram: 16384))) {
            XCTAssertEqual($0 as? PlacementRefusal, PlacementRefusal(code: "not_enough_room", message: "not enough RAM", resource: "ram_mb", needed: 16384, free: 8192))
        }
        XCTAssertThrowsError(try Placement.choose(pool, wish(ram: 2048, disk: 60))) {
            XCTAssertEqual(($0 as? PlacementRefusal)?.resource, "disk_gb")
            XCTAssertEqual(($0 as? PlacementRefusal)?.needed, 60)
        }
        XCTAssertNoThrow(try Placement.choose(pool, wish(ram: 8192, disk: 20)), "exactly enough is enough")
    }

    func testRequestsAreReadStrictly() throws {
        func parse(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> CreateWorkloadOperatorRequest {
            var body: [String: Any] = ["name": "demo", "kind": "vm", "cpu": 2, "ram_mb": 2048, "disk_gb": 20]
            change?(&body)
            return try CreateWorkloadOperatorRequest(body: JSONSerialization.data(withJSONObject: body))
        }
        XCTAssertEqual(try parse().gpuMode, "none")
        XCTAssertEqual(try parse { $0["machine"] = "dgx-spark" }.machine, "dgx-spark")
        for bad: (inout [String: Any]) -> Void in [{ $0["name"] = "Bad Name" }, { $0["kind"] = "metal" }, { $0["cpu"] = 0 }, { $0["ram_mb"] = 100 }, { $0["disk_gb"] = 0 },
                                                   { $0["machine"] = "../x" }, { $0["image"] = "--privileged" }, { $0["x"] = 1 }, { $0["gpu_mode"] = "all" }] {
            XCTAssertThrowsError(try parse(bad))
        }
        XCTAssertNoThrow(try ConfirmRequest(body: Data(#"{"confirm":true}"#.utf8)))
        for bad in [#"{"confirm":false}"#, "{}", #"{"confirm":"yes"}"#, #"{"confirm":1}"#, #"{"confirm":true,"x":1}"#] { XCTAssertThrowsError(try ConfirmRequest(body: Data(bad.utf8)), bad) }
    }

    func testLoopbackAndPrivateAddressesOnly() {
        for good in ["127.0.0.1", "10.1.2.3", "172.16.0.9", "172.31.255.255", "192.168.100.1"] { XCTAssertTrue(IPv4.isLoopbackOrPrivate(good), good) }
        for bad in ["8.8.8.8", "172.32.0.1", "192.169.1.1", "169.254.169.254", "0.0.0.0", "", "localhost", "10.0.0", "10.0.0.256", "1.1.1.1 "] { XCTAssertFalse(IPv4.isLoopbackOrPrivate(bad), bad) }
    }
}
