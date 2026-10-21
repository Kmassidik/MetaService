import XCTest
@testable import RootCore

final class MachineStatsTests: XCTestCase {
    private func answer(processes: String = "[]", cores: String = "[1.0, 2.0]", extra: String = "", disks: String = "[]") -> Data {
        Data("""
        {"taken_at":"2026-10-21T10:00:00Z","measuring":false,"uptime_seconds":5,
         "cpu":{"core_count":2,"total_percent":1.5,"cores_percent":\(cores),"load":{"one":1.0,"five":null,"fifteen":0.5}},
         "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
         "disks":\(disks),
         "network":{"received_total_bytes":1,"sent_total_bytes":2,"received_bytes_per_second":null,"sent_bytes_per_second":null},
         "processes":\(processes)\(extra)}
        """.utf8)
    }

    private func process(_ n: Int, name: String = "node", cpu: String = "1.0") -> String {
        "{\"pid\":\(n),\"name\":\"\(name)\",\"user\":\"kurnia\",\"cpu_percent\":\(cpu),\"memory_bytes\":10}"
    }

    func testAGoodAnswerIsReadAsItIs() throws {
        let stats = try MachineStats.parse(answer(processes: "[\(process(1))]"))
        XCTAssertEqual(stats.cpu.coreCount, 2)
        XCTAssertEqual(stats.cpu.coresPercent, [1.0, 2.0])
        XCTAssertNil(stats.cpu.load.five)
        XCTAssertNil(stats.network.receivedBytesPerSecond)
        XCTAssertNil(stats.gpus, "no gpus key stays no gpus key, never an empty list or zeros")
        XCTAssertEqual(stats.processes.first?.name, "node")
    }

    func testMeasuringAnswerKeepsItsNullsAndNeverBecomesZero() throws {
        let data = Data("""
        {"taken_at":"2026-10-21T10:00:00Z","measuring":true,"uptime_seconds":5,
         "cpu":{"core_count":2,"total_percent":null,"cores_percent":null,"load":{"one":null,"five":null,"fifteen":null}},
         "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
         "disks":[],"network":{"received_total_bytes":1,"sent_total_bytes":2,"received_bytes_per_second":null,"sent_bytes_per_second":null},
         "processes":[\(process(1, cpu: "null"))]}
        """.utf8)
        let stats = try MachineStats.parse(data)
        XCTAssertTrue(stats.measuring)
        XCTAssertNil(stats.cpu.totalPercent)
        XCTAssertNil(stats.cpu.coresPercent)
        XCTAssertNil(stats.processes[0].cpuPercent)
    }

    func testAtMostFifteenProcessesAreKept() throws {
        let many = (1...40).map { process($0) }.joined(separator: ",")
        XCTAssertEqual(try MachineStats.parse(answer(processes: "[\(many)]")).processes.count, MachineStats.maxProcesses)
        XCTAssertEqual(MachineStats.maxProcesses, 15)
    }

    func testNamesAndUsersAreCutAtSixtyFourCharacters() throws {
        let long = String(repeating: "é", count: 200)
        let stats = try MachineStats.parse(answer(processes: "[\(process(1, name: long))]"))
        XCTAssertEqual(stats.processes[0].name.count, 64)
    }

    func testHostileTextIsKeptAsTextNotChanged() throws {
        let stats = try MachineStats.parse(answer(processes: "[\(process(1, name: "<img src=x onerror=alert(1)>"))]"))
        XCTAssertEqual(stats.processes[0].name, "<img src=x onerror=alert(1)>")
    }

    func testPercentagesAreHeldInsideTheirRange() throws {
        let stats = try MachineStats.parse(answer(cores: "[150.0, -3.0]"))
        XCTAssertEqual(stats.cpu.coresPercent, [100.0, 0.0])
    }

    func testMoreCoresThanTheLimitAreCut() throws {
        let cores = "[" + Array(repeating: "1.0", count: 3000).joined(separator: ",") + "]"
        XCTAssertEqual(try MachineStats.parse(answer(cores: cores)).cpu.coresPercent?.count, MachineStats.maxCores)
    }

    func testMoreDisksThanTheLimitAreCut() throws {
        let disk = "{\"mount\":\"/\",\"name\":\"d\",\"fs\":\"apfs\",\"total_bytes\":10,\"used_bytes\":4,\"free_bytes\":6}"
        let disks = "[" + Array(repeating: disk, count: 40).joined(separator: ",") + "]"
        XCTAssertEqual(try MachineStats.parse(answer(disks: disks)).disks.count, MachineStats.maxDisks)
    }

    func testAnAnswerMissingARequiredPartIsRefused() {
        XCTAssertThrowsError(try MachineStats.parse(Data("{\"taken_at\":\"x\"}".utf8)))
        XCTAssertThrowsError(try MachineStats.parse(Data("not json".utf8)))
    }

    func testAnAnswerBiggerThanTheLimitIsRefused() {
        let padded = answer(extra: ",\"junk\":\"" + String(repeating: "x", count: MachineStats.maxAnswerBytes) + "\"")
        XCTAssertThrowsError(try MachineStats.parse(padded))
    }

    func testTheCommandLineIsNeverKept() throws {
        let sneaky = "[{\"pid\":1,\"name\":\"node\",\"user\":\"k\",\"cpu_percent\":1.0,\"memory_bytes\":1,\"cmdline\":\"SECRET-FAKE\",\"command\":\"SECRET-FAKE\"}]"
        let stats = try MachineStats.parse(answer(processes: sneaky))
        let sent = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        XCTAssertFalse(sent.contains("SECRET-FAKE"))
    }

    func testItEncodesWithSnakeCaseKeysAndNoGpusKeyWhenThereAreNone() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let text = String(decoding: try encoder.encode(try MachineStats.parse(answer())), as: UTF8.self)
        XCTAssertTrue(text.contains("\"taken_at\""))
        XCTAssertFalse(text.contains("gpus"))
        XCTAssertTrue(text.contains("\"total_percent\":1.5"))
    }

    func testAMissingNumberIsWrittenAsNullNotLeftOutAndNotZero() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let stats = try MachineStats.parse(answer(processes: "[\(process(1, cpu: "null"))]"))
        let text = String(decoding: try encoder.encode(stats), as: UTF8.self)
        XCTAssertTrue(text.contains("\"received_bytes_per_second\":null"), text)
        XCTAssertTrue(text.contains("\"cpu_percent\":null"), text)
        XCTAssertTrue(text.contains("\"five\":null"), text)
    }
}
