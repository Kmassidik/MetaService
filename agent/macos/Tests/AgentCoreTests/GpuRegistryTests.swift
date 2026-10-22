import XCTest
@testable import AgentCore

/// A trimmed copy of what `ioreg -c IOAccelerator` shows on an Apple Silicon Mac.
private let appleRegistryEntry = """
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>IOClass</key><string>AGXAcceleratorG14X</string>
  <key>model</key><string>Apple M2 Pro</string>
  <key>gpu-core-count</key><integer>16</integer>
  <key>PerformanceStatistics</key><dict>
    <key>Device Utilization %</key><integer>10</integer>
    <key>Alloc system memory</key><integer>2082193408</integer>
    <key>In use system memory</key><integer>337084416</integer>
    <key>Renderer Utilization %</key><integer>10</integer>
  </dict>
</dict></plist>
"""

private func entry(_ xml: String) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(from: Data(xml.utf8), options: [], format: nil)
    return try XCTUnwrap(object as? [String: Any])
}

private let machineMemory: UInt64 = 34_359_738_368

private func snapshot(gpus: [GpuReading]) -> StatsSnapshot {
    StatsSnapshot(takenAt: Date(timeIntervalSince1970: 1_800_000_000), uptimeSeconds: 1, cores: [CoreTicks(busy: 0, total: 0)], load: [nil, nil, nil],
                  memory: MemoryReading(totalBytes: machineMemory, usedBytes: 5, cachedBytes: 3, freeBytes: 2, swapTotalBytes: 0, swapUsedBytes: 0), disks: [],
                  receivedTotalBytes: 0, sentTotalBytes: 0, processes: [], extras: StatsExtras(gpus: gpus))
}

final class GpuRegistryTests: XCTestCase {
    func testAnAppleEntryGivesNameUseAndMemoryInUse() throws {
        let reading = try XCTUnwrap(AppleGpuRegistry.reading(from: entry(appleRegistryEntry), brand: "Apple M2 Pro"))
        XCTAssertEqual(reading, GpuReading(name: "Apple M2 Pro GPU", vendor: "apple", utilizationPercent: 10, memoryUsedBytes: 337_084_416, sharesSystemMemory: true))
    }

    func testTheBrandNamesTheChipWhenTheEntryHasNoModel() throws {
        var properties = try entry(appleRegistryEntry)
        properties["model"] = nil
        XCTAssertEqual(AppleGpuRegistry.reading(from: properties, brand: "Apple M3 Max")?.name, "Apple M3 Max GPU")
        XCTAssertEqual(AppleGpuRegistry.reading(from: properties, brand: nil)?.name, "Apple GPU")
    }

    func testAModelGivenAsBytesIsReadAndAnAlreadyNamedGpuIsNotDoubled() throws {
        var properties = try entry(appleRegistryEntry)
        properties["model"] = Data("Apple M1 GPU\0".utf8)
        XCTAssertEqual(AppleGpuRegistry.reading(from: properties, brand: nil)?.name, "Apple M1 GPU")
    }

    func testOutOfRangeAndMissingCountersAreNilNeverZero() throws {
        var properties = try entry(appleRegistryEntry)
        properties["PerformanceStatistics"] = ["Device Utilization %": 250, "In use system memory": -5]
        XCTAssertNil(AppleGpuRegistry.reading(from: properties, brand: nil), "nothing readable: no chip")
        properties["PerformanceStatistics"] = ["In use system memory": 4096]
        let onlyMemory = try XCTUnwrap(AppleGpuRegistry.reading(from: properties, brand: nil))
        XCTAssertEqual(onlyMemory.memoryUsedBytes, 4096)
        XCTAssertNil(onlyMemory.utilizationPercent)
    }

    func testAnEntryWithoutStatisticsIsNotAChip() throws {
        var properties = try entry(appleRegistryEntry)
        properties["PerformanceStatistics"] = nil
        XCTAssertNil(AppleGpuRegistry.reading(from: properties, brand: nil))
    }

    func testAnotherMakerIsUnknownAndDoesNotShareTheMachinesMemory() throws {
        var properties = try entry(appleRegistryEntry)
        properties["IOClass"] = "AMDRadeonAccelerator"
        properties["model"] = "Radeon Pro 5500M"
        let reading = try XCTUnwrap(AppleGpuRegistry.reading(from: properties, brand: "Apple M2 Pro"))
        XCTAssertEqual(reading.vendor, "unknown")
        XCTAssertFalse(reading.sharesSystemMemory)
    }

    func testTheAnswerSharesTheMachinesMemoryAsTheTotalAndHasNoTemperaturePowerOrClock() throws {
        let reading = try XCTUnwrap(AppleGpuRegistry.reading(from: entry(appleRegistryEntry), brand: nil))
        let stats = try StatsSampler(source: Fixed(snapshot(gpus: [reading]))).sample()
        let gpu = try XCTUnwrap(stats.gpus?.first)
        XCTAssertEqual(gpu.memoryUsedBytes, 337_084_416)
        XCTAssertEqual(gpu.memoryTotalBytes, machineMemory)
        XCTAssertEqual(gpu.utilizationPercent, 10)
        let text = String(decoding: try StatsJson.encode(stats), as: UTF8.self)
        XCTAssertTrue(text.contains("\"vendor\":\"apple\""))
        for key in ["power_watts", "power_limit_watts", "fan_percent", "clock_mhz"] { XCTAssertFalse(text.contains(key), "\(key) must be left out on a Mac") }
        XCTAssertTrue(text.contains("\"temperature_celsius\":null"), "the existing key stays, as null")
    }

    func testMemoryInUseNeverPassesTheTotalAndAtMostEightChipsAreKept() throws {
        let huge = GpuReading(name: String(repeating: "g", count: 200), vendor: "apple", utilizationPercent: 33.33, memoryUsedBytes: UInt64.max, sharesSystemMemory: true)
        let stats = try StatsSampler(source: Fixed(snapshot(gpus: Array(repeating: huge, count: 12)))).sample()
        let gpus = try XCTUnwrap(stats.gpus)
        XCTAssertEqual(gpus.count, 8)
        XCTAssertEqual(gpus[0].name.count, 64)
        XCTAssertEqual(gpus[0].memoryUsedBytes, machineMemory)
        XCTAssertEqual(gpus[0].utilizationPercent, 33.3)
    }

    func testNoChipLeavesTheGpusKeyOut() throws {
        let stats = try StatsSampler(source: Fixed(snapshot(gpus: []))).sample()
        XCTAssertNil(stats.gpus)
        XCTAssertFalse(String(decoding: try StatsJson.encode(stats), as: UTF8.self).contains("\"gpus\""))
    }
}

private final class Fixed: StatsSource {
    private let value: StatsSnapshot
    init(_ value: StatsSnapshot) { self.value = value }
    func read(includeProcesses: Bool) throws -> StatsSnapshot { value }
}
