import XCTest
@testable import RootCore

final class HardwareTests: XCTestCase {
    private static let spark: [String: Any] = [
        "system": "NVIDIA DGX Spark",
        "core_types": [["name": "Cortex-X925", "cores": 10, "max_mhz": 4004], ["name": "Cortex-A725", "cores": 10, "max_mhz": 2860]],
        "disks": [["model": "ESL04TBTLCZ-27J2-TYN", "size_gb": 4096, "kind": "nvme"]],
    ]

    private func facts(_ change: (inout [String: Any]) -> Void) throws -> FactsReport {
        var body = RequestsTests.goodHeartbeat()
        var facts = body["facts"] as! [String: Any]
        change(&facts)
        body["facts"] = facts
        return try HeartbeatRequest(body: JSONSerialization.data(withJSONObject: body)).facts
    }

    private func hardware(_ value: Any?) throws -> HardwareReport? {
        try facts { if let value { $0["hardware"] = value } }.hardware
    }

    private func gpu(_ extra: [String: Any]) throws -> GpuInfo? {
        try facts { $0["gpu"] = [(["vendor": "nvidia", "model": "NVIDIA GB10"] as [String: Any]).merging(extra) { $1 }] }.gpu.first
    }

    private func with(_ key: String, _ value: Any) -> [String: Any] {
        var report = Self.spark
        report[key] = value
        return report
    }

    func testWhatTheHelperSaysIsAcceptedAsItSaysIt() throws {
        XCTAssertEqual(try hardware(Self.spark), HardwareReport(
            system: "NVIDIA DGX Spark",
            coreTypes: [.init(name: "Cortex-X925", cores: 10, maxMhz: 4004), .init(name: "Cortex-A725", cores: 10, maxMhz: 2860)],
            disks: [.init(model: "ESL04TBTLCZ-27J2-TYN", sizeGb: 4096, kind: "nvme")]))
    }

    func testAnOlderHelperAndANullGiveNil() throws {
        XCTAssertNil(try hardware(nil))
        XCTAssertNil(try hardware(NSNull()))
    }

    func testEveryPartIsOptional() throws {
        XCTAssertEqual(try hardware(["system": "Dell PowerEdge R7525"]), HardwareReport(system: "Dell PowerEdge R7525"))
        XCTAssertEqual(try hardware(["core_types": [["name": "AMD EPYC 7763 64-Core Processor", "cores": 64]]]),
                       HardwareReport(coreTypes: [.init(name: "AMD EPYC 7763 64-Core Processor", cores: 64)]))
        XCTAssertEqual(try hardware(["disks": [["model": "WDC WD40EFRX", "size_gb": 4000, "kind": "hdd"]], "system": NSNull()]),
                       HardwareReport(disks: [.init(model: "WDC WD40EFRX", sizeGb: 4000, kind: "hdd")]))
        XCTAssertNil(try hardware([String: Any]()), "a report that says nothing is no report")
    }

    func testTextsAreCleanedLikeTheCpuName() throws {
        let report = try XCTUnwrap(try hardware([
            "system": "  ASUS\tROG\u{0}  CROSSHAIR \u{1B}[31m VIII\n",
            "core_types": [["name": String(repeating: "x", count: 300), "cores": 8], ["name": "<b>A</b>", "cores": 4]],
            "disks": [["model": "Samsung  SSD\u{7F} 990 PRO", "size_gb": 2000, "kind": "nvme"]],
        ]))
        XCTAssertEqual(report.system, "ASUS ROG CROSSHAIR [31m VIII")
        XCTAssertEqual(report.coreTypes?.map(\.name.count), [120, 8])
        XCTAssertEqual(report.coreTypes?.last?.name, "<b>A</b>", "markup is kept as plain text for the panel to show as text")
        XCTAssertEqual(report.disks?.first?.model, "Samsung SSD 990 PRO")
    }

    func testAnItemWhoseNameCleansToNothingIsDroppedAndAnEmptiedReportIsNone() throws {
        let report = try hardware(["system": " \t ", "core_types": [["name": "\u{0}", "cores": 4], ["name": "Cortex-A72", "cores": 4]],
                                   "disks": [["model": "  ", "size_gb": 32, "kind": "ssd"]]])
        XCTAssertEqual(report, HardwareReport(coreTypes: [.init(name: "Cortex-A72", cores: 4)]))
        XCTAssertNil(try hardware(["system": "\n", "disks": [["model": "", "size_gb": 32, "kind": "ssd"]]]))
    }

    func testAnUnknownKeyIsRefused() {
        let bad: [[String: Any]] = [
            with("serial", "ABC123"),
            with("core_types", [["name": "A", "cores": 1, "threads": 2]]),
            with("disks", [["model": "A", "size_gb": 1, "kind": "ssd", "serial": "X"]]),
        ]
        for item in bad { XCTAssertThrowsError(try hardware(item), "\(item)") }
    }

    func testAWrongTypeOrAValueOutOfRangeIsRefused() {
        let bad: [Any] = [
            "Spark", [Self.spark],
            with("system", 5), with("system", String(repeating: "z", count: 5000)),
            with("core_types", [Any]()), with("core_types", ["Cortex-A72"]), with("core_types", Array(repeating: ["name": "A", "cores": 1] as [String: Any], count: 9)),
            with("core_types", [["cores": 4]]), with("core_types", [["name": "A"]]), with("core_types", [["name": 5, "cores": 4]]),
            with("core_types", [["name": "A", "cores": 0]]), with("core_types", [["name": "A", "cores": 100_001]]), with("core_types", [["name": "A", "cores": 2.5]]),
            with("core_types", [["name": "A", "cores": true]]), with("core_types", [["name": "A", "cores": 4, "max_mhz": 0]]),
            with("core_types", [["name": "A", "cores": 4, "max_mhz": 20_001]]), with("core_types", [["name": "A", "cores": 4, "max_mhz": "3 GHz"]]),
            with("disks", [Any]()), with("disks", Array(repeating: ["model": "A", "size_gb": 1, "kind": "ssd"] as [String: Any], count: 9)),
            with("disks", [["model": "A", "size_gb": 1]]), with("disks", [["model": "A", "kind": "ssd"]]), with("disks", [["size_gb": 1, "kind": "ssd"]]),
            with("disks", [["model": "A", "size_gb": 0, "kind": "ssd"]]), with("disks", [["model": "A", "size_gb": 100_000_001, "kind": "ssd"]]),
            with("disks", [["model": "A", "size_gb": 1, "kind": "usb"]]), with("disks", [["model": "A", "size_gb": 1, "kind": "NVMe"]]),
        ]
        for item in bad { XCTAssertThrowsError(try hardware(item), "\(item)") }
    }

    func testTheGpuDetailsAreAccepted() throws {
        let card = try gpu(["memory_mb": 32768, "architecture": "Blackwell", "compute_capability": "12.0", "driver_version": "580.178.04",
                            "max_clock_mhz": 3090, "uses_system_memory": false])
        XCTAssertEqual(card, GpuInfo(vendor: "nvidia", model: "NVIDIA GB10", memoryMb: 32768, architecture: "Blackwell", computeCapability: "12.0",
                                     driverVersion: "580.178.04", maxClockMhz: 3090, usesSystemMemory: false))
        let spark = try XCTUnwrap(try gpu(["architecture": "Blackwell", "compute_capability": "12.1", "uses_system_memory": true]))
        XCTAssertNil(spark.memoryMb)
        XCTAssertEqual(spark.usesSystemMemory, true)
        XCTAssertEqual(try gpu(["architecture": "  Ada\tLovelace\u{0}"])?.architecture, "Ada Lovelace")
    }

    func testAGpuWithoutTheDetailsIsAsBefore() throws {
        XCTAssertEqual(try gpu(["memory_mb": 131072]), GpuInfo(vendor: "nvidia", model: "NVIDIA GB10", memoryMb: 131072))
        XCTAssertEqual(try gpu(["architecture": NSNull(), "driver_version": NSNull()]), GpuInfo(vendor: "nvidia", model: "NVIDIA GB10", memoryMb: nil))
    }

    func testBadGpuDetailsAreRefused() {
        let bad: [[String: Any]] = [
            ["pcie_gen": 5], ["architecture": 5], ["architecture": String(repeating: "B", count: 33)],
            ["compute_capability": "12"], ["compute_capability": "12.0.1"], ["compute_capability": "123.0"], ["compute_capability": "sm_120"], ["compute_capability": 12.0],
            ["driver_version": ""], ["driver_version": "-580"], ["driver_version": "580 178"], ["driver_version": String(repeating: "5", count: 33)], ["driver_version": "<b>"],
            ["max_clock_mhz": 0], ["max_clock_mhz": 20_001], ["max_clock_mhz": "3090"], ["uses_system_memory": "yes"], ["uses_system_memory": 1],
        ]
        for item in bad { XCTAssertThrowsError(try gpu(item), "\(item)") }
    }
}
