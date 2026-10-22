import XCTest
@testable import RootCore

private func answer(gpus: String?) -> Data {
    let gpuPart = gpus.map { ",\"gpus\":\($0)" } ?? ""
    return Data("""
    {"taken_at":"2026-10-21T10:00:00Z","measuring":false,"uptime_seconds":5,
     "cpu":{"core_count":2,"total_percent":1.5,"cores_percent":[1.0,2.0],"load":{"one":1.0,"five":null,"fifteen":0.5}},
     "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
     "disks":[],"network":{"received_total_bytes":1,"sent_total_bytes":2,"received_bytes_per_second":null,"sent_bytes_per_second":null},
     "processes":[]\(gpuPart)}
    """.utf8)
}

private func gpu(_ fields: String) -> String {
    "{\"name\":\"RTX\",\"utilization_percent\":50,\"memory_used_bytes\":10,\"memory_total_bytes\":100,\"temperature_celsius\":60\(fields)}"
}

private func firstGpu(_ fields: String) throws -> MachineStats.Gpu {
    try XCTUnwrap(try MachineStats.parse(answer(gpus: "[\(gpu(fields))]")).gpus?.first)
}

final class MachineStatsGpuTests: XCTestCase {
    func testTheNewOptionalFieldsPassThroughWhenInRange() throws {
        let kept = try firstGpu(",\"vendor\":\"nvidia\",\"power_watts\":310.5,\"power_limit_watts\":575,\"fan_percent\":30,\"clock_mhz\":2400,\"processes\":[{\"name\":\"python3\",\"memory_bytes\":4096}]")
        XCTAssertEqual(kept.vendor, "nvidia")
        XCTAssertEqual(kept.powerWatts, 310.5)
        XCTAssertEqual(kept.powerLimitWatts, 575)
        XCTAssertEqual(kept.fanPercent, 30)
        XCTAssertEqual(kept.clockMhz, 2400)
        XCTAssertEqual(kept.processes, [.init(name: "python3", memoryBytes: 4096)])
    }

    func testOutOfRangeNumbersAreDroppedNeverClamped() throws {
        let kept = try firstGpu(",\"power_watts\":2001,\"power_limit_watts\":-1,\"fan_percent\":101,\"clock_mhz\":0")
        XCTAssertNil(kept.powerWatts)
        XCTAssertNil(kept.powerLimitWatts)
        XCTAssertNil(kept.fanPercent)
        XCTAssertNil(kept.clockMhz)
        let hostile = try MachineStats.parse(answer(gpus: "[{\"name\":\"X\",\"utilization_percent\":140,\"memory_used_bytes\":-5,\"memory_total_bytes\":9007199254740993,\"temperature_celsius\":900}]")).gpus?.first
        XCTAssertNil(hostile?.utilizationPercent, "dropped, not clamped to 100")
        XCTAssertNil(hostile?.memoryUsedBytes, "dropped, not clamped to 0")
        XCTAssertNil(hostile?.memoryTotalBytes)
        XCTAssertNil(hostile?.temperatureCelsius)
    }

    func testTheEdgesOfTheRangesAreKept() throws {
        let kept = try firstGpu(",\"power_watts\":0,\"power_limit_watts\":2000,\"fan_percent\":100,\"clock_mhz\":20000")
        XCTAssertEqual([kept.powerWatts, kept.powerLimitWatts, kept.fanPercent, kept.clockMhz], [0, 2000, 100, 20000])
    }

    func testAnUnknownVendorBecomesUnknownAndHostileTextStaysText() throws {
        XCTAssertEqual(try firstGpu(",\"vendor\":\"<script>alert(1)</script>\"").vendor, "unknown")
        let named = try MachineStats.parse(answer(gpus: "[{\"name\":\"<img src=x onerror=alert(1)>\",\"utilization_percent\":null,\"memory_used_bytes\":null,\"memory_total_bytes\":null,\"temperature_celsius\":null,\"processes\":[{\"name\":\"<b>x</b>\",\"memory_bytes\":1}]}]")).gpus?.first
        XCTAssertEqual(named?.name, "<img src=x onerror=alert(1)>")
        XCTAssertEqual(named?.processes?.first?.name, "<b>x</b>")
    }

    func testProgramsAreCutAtEightAndTheirNamesAtSixtyFourAndBadMemoryDropsTheProgram() throws {
        let long = String(repeating: "p", count: 200)
        let programs = (0..<12).map { "{\"name\":\"\(long)\",\"memory_bytes\":\($0)}" }.joined(separator: ",")
        let kept = try firstGpu(",\"processes\":[\(programs)]")
        XCTAssertEqual(kept.processes?.count, 8)
        XCTAssertEqual(kept.processes?.first?.name.count, 64)
        XCTAssertEqual(try firstGpu(",\"processes\":[{\"name\":\"a\",\"memory_bytes\":-4},{\"name\":\"b\",\"memory_bytes\":4}]").processes, [.init(name: "b", memoryBytes: 4)])
    }

    func testAnEmptyProgramListStaysAnEmptyListAndAnAbsentOneStaysAbsent() throws {
        XCTAssertEqual(try firstGpu(",\"processes\":[]").processes, [])
        XCTAssertNil(try firstGpu("").processes)
    }

    func testMoreThanEightGpusAreCutAndNoneKeepsNoKey() throws {
        let many = Array(repeating: gpu(""), count: 12).joined(separator: ",")
        XCTAssertEqual(try MachineStats.parse(answer(gpus: "[\(many)]")).gpus?.count, 8)
        XCTAssertNil(try MachineStats.parse(answer(gpus: "[]")).gpus)
    }

    func testAbsentNewFieldsAreNotWrittenAsZeroOrNull() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(decoding: try encoder.encode(try MachineStats.parse(answer(gpus: "[\(gpu(""))]"))), as: UTF8.self)
        for key in ["vendor", "power_watts", "power_limit_watts", "fan_percent", "clock_mhz", "\"processes\":[{"] { XCTAssertFalse(text.contains(key), key) }
    }
}

final class HistoryGpuTests: XCTestCase {
    private func reading(gpus: [MachineStats.Gpu]?) throws -> MachineStats {
        var stats = try MachineStats.parse(answer(gpus: nil))
        stats.gpus = gpus
        return stats
    }

    private func gpuOf(use: Double?, memory: Int?, temperature: Double?, power: Double?) -> MachineStats.Gpu {
        MachineStats.Gpu(name: "g", utilizationPercent: use, memoryUsedBytes: memory, memoryTotalBytes: 100, temperatureCelsius: temperature, powerWatts: power)
    }

    func testEachGpuGetsItsSeriesByIndex() throws {
        let stats = try reading(gpus: [gpuOf(use: 40, memory: 10, temperature: 55, power: 200), gpuOf(use: 5, memory: 20, temperature: nil, power: nil)])
        let point = try XCTUnwrap(HistoryPoint(stats: stats, at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(point.gpus, [HistoryGpu(index: 0, utilizationPercent: 40, memoryUsedBytes: 10, temperatureCelsius: 55, powerWatts: 200),
                                    HistoryGpu(index: 1, utilizationPercent: 5, memoryUsedBytes: 20)])
    }

    func testAGpuWithNoNumberLeavesAGapButKeepsTheOthersIndex() throws {
        let stats = try reading(gpus: [gpuOf(use: nil, memory: nil, temperature: nil, power: nil), gpuOf(use: 7, memory: nil, temperature: nil, power: nil)])
        XCTAssertEqual(HistoryPoint(stats: stats, at: Date())?.gpus, [HistoryGpu(index: 1, utilizationPercent: 7)])
    }

    func testNoGpuMeansNoSeriesAndNoKey() throws {
        for gpus in [nil, [], [gpuOf(use: nil, memory: nil, temperature: nil, power: nil)]] as [[MachineStats.Gpu]?] {
            let point = try XCTUnwrap(HistoryPoint(stats: reading(gpus: gpus), at: Date()))
            XCTAssertNil(point.gpus)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            XCTAssertFalse(String(decoding: try encoder.encode(point), as: UTF8.self).contains("gpus"))
        }
    }

    func testTheJsonUsesTheContractsNamesAndLeavesOutWhatIsMissing() throws {
        let stats = try reading(gpus: [gpuOf(use: 40, memory: nil, temperature: 55, power: nil)])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(decoding: try encoder.encode(try XCTUnwrap(HistoryPoint(stats: stats, at: Date()))), as: UTF8.self)
        XCTAssertTrue(text.contains("\"gpus\":[{"), text)
        XCTAssertTrue(text.contains("\"utilization_percent\":40"))
        XCTAssertTrue(text.contains("\"temperature_celsius\":55"))
        XCTAssertFalse(text.contains("memory_used_bytes"))
        XCTAssertFalse(text.contains("power_watts"))
    }

    func testTheRingKeepsGpuSeriesInsideTheSameThreeHundredSixtyPoints() throws {
        var history = StatsHistory(capacity: 360)
        let stats = try reading(gpus: [gpuOf(use: 1, memory: 1, temperature: 1, power: 1)])
        for second in 0..<400 { history.record("m", try XCTUnwrap(HistoryPoint(stats: stats, at: Date(timeIntervalSince1970: Double(second))))) }
        let kept = history.points("m", last: 360)
        XCTAssertEqual(kept.count, 360)
        XCTAssertTrue(kept.allSatisfy { $0.gpus?.count == 1 })
    }
}
