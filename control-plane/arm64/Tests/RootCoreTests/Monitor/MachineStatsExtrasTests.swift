import XCTest
@testable import RootCore

/// The optional numbers a helper may add: kept when they are in range, left out (never clamped, never 0) when they are not.
final class MachineStatsExtrasTests: XCTestCase {
    private func answer(cpu extraCpu: String = "", network extraNetwork: String = "", top extraTop: String = "", process extraProcess: String = "") -> Data {
        Data("""
        {"taken_at":"2026-10-21T10:00:00Z","measuring":false,"uptime_seconds":5,
         "cpu":{"core_count":4,"total_percent":1.5,"cores_percent":[1.0,2.0,3.0,4.0],"load":{"one":1.0,"five":null,"fifteen":0.5}\(extraCpu)},
         "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
         "disks":[],
         "network":{"received_total_bytes":1,"sent_total_bytes":2,"received_bytes_per_second":3.0,"sent_bytes_per_second":4.0\(extraNetwork)}\(extraTop),
         "processes":[{"pid":1,"name":"node","user":"k","cpu_percent":1.0,"memory_bytes":10\(extraProcess)}]}
        """.utf8)
    }

    func testAnOlderHelperWithNoExtrasGivesNoExtras() throws {
        let stats = try MachineStats.parse(answer())
        XCTAssertNil(stats.cpu.physicalCores)
        XCTAssertNil(stats.cpu.coreOf)
        XCTAssertNil(stats.cpu.breakdown)
        XCTAssertNil(stats.diskIo)
        XCTAssertNil(stats.processCount)
        XCTAssertNil(stats.network.errorsInTotal)
        XCTAssertNil(stats.processes[0].threads)
        let text = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        for key in ["physicalCores", "coreOf", "clusters", "breakdown", "frequencyMhz", "temperatureCelsius", "diskIo", "processCount", "errorsInTotal", "threads"] {
            XCTAssertFalse(text.contains(key), "\(key) must stay out of the answer")
        }
    }

    func testGoodExtrasAreKept() throws {
        let cpu = ",\"physical_cores\":2,\"core_of\":[0,0,1,1],\"clusters\":[{\"name\":\"Performance\",\"logical\":2},{\"name\":\"Efficiency\",\"logical\":2}],"
            + "\"breakdown\":{\"user\":10.5,\"system\":5.0,\"nice\":0.0,\"idle\":80.0,\"iowait\":4.5,\"irq\":0.0,\"softirq\":0.0,\"steal\":0.0},"
            + "\"frequency_mhz\":{\"average\":3200.5,\"max\":4900.0},\"temperature_celsius\":61.5"
        let top = ",\"disk_io\":{\"read_bytes_per_second\":1000.0,\"write_bytes_per_second\":2000.0},\"process_count\":321"
        let network = ",\"errors_in_total\":1,\"errors_out_total\":2,\"drops_in_total\":3,\"drops_out_total\":4"
        let stats = try MachineStats.parse(answer(cpu: cpu, network: network, top: top, process: ",\"threads\":12"))
        XCTAssertEqual(stats.cpu.physicalCores, 2)
        XCTAssertEqual(stats.cpu.coreOf, [0, 0, 1, 1])
        XCTAssertEqual(stats.cpu.clusters?.map(\.name), ["Performance", "Efficiency"])
        XCTAssertEqual(stats.cpu.breakdown?.iowait, 4.5)
        XCTAssertEqual(stats.cpu.frequencyMhz, MachineStats.Frequency(average: 3200.5, max: 4900))
        XCTAssertEqual(stats.cpu.temperatureCelsius, 61.5)
        XCTAssertEqual(stats.diskIo, MachineStats.DiskIo(readBytesPerSecond: 1000, writeBytesPerSecond: 2000))
        XCTAssertEqual(stats.processCount, 321)
        XCTAssertEqual([stats.network.errorsInTotal, stats.network.errorsOutTotal, stats.network.dropsInTotal, stats.network.dropsOutTotal], [1, 2, 3, 4])
        XCTAssertEqual(stats.processes[0].threads, 12)
        let text = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        XCTAssertTrue(text.contains("physicalCores") && text.contains("diskIo") && text.contains("threads"))
    }

    func testMoreCoresThanCpusAndAWrongSizedGroupingAreDropped() throws {
        let stats = try MachineStats.parse(answer(cpu: ",\"physical_cores\":9,\"core_of\":[0,1,2]"))
        XCTAssertNil(stats.cpu.physicalCores)
        XCTAssertNil(stats.cpu.coreOf, "three entries for four CPUs")
        XCTAssertNil(try MachineStats.parse(answer(cpu: ",\"physical_cores\":0")).cpu.physicalCores)
        XCTAssertNil(try MachineStats.parse(answer(cpu: ",\"core_of\":[0,1,2,7]")).cpu.coreOf, "a core number past the CPU count")
        XCTAssertNil(try MachineStats.parse(answer(cpu: ",\"core_of\":[0,1,2,-1]")).cpu.coreOf)
    }

    func testClustersAreCappedCutAndDroppedWhenAbsurd() throws {
        let many = (0..<20).map { "{\"name\":\"c\($0)\",\"logical\":1}" }.joined(separator: ",")
        XCTAssertEqual(try MachineStats.parse(answer(cpu: ",\"clusters\":[\(many)]")).cpu.clusters?.count, MachineStats.maxClusters)
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(try MachineStats.parse(answer(cpu: ",\"clusters\":[{\"name\":\"\(long)\",\"logical\":2}]")).cpu.clusters?.first?.name.count, MachineStats.maxTextCharacters)
        XCTAssertNil(try MachineStats.parse(answer(cpu: ",\"clusters\":[{\"name\":\"a\",\"logical\":0},{\"name\":\"b\",\"logical\":99}]")).cpu.clusters)
    }

    func testABreakdownStateOutOfRangeIsDroppedNotClamped() throws {
        let stats = try MachineStats.parse(answer(cpu: ",\"breakdown\":{\"user\":150.0,\"system\":-1.0,\"idle\":50.0}"))
        XCTAssertNil(stats.cpu.breakdown?.user)
        XCTAssertNil(stats.cpu.breakdown?.system)
        XCTAssertEqual(stats.cpu.breakdown?.idle, 50)
        XCTAssertNil(try MachineStats.parse(answer(cpu: ",\"breakdown\":{\"user\":999.0}")).cpu.breakdown, "nothing left of it")
    }

    func testFrequencyAndTemperatureOutOfRangeAreDroppedNotZero() throws {
        let broken = try MachineStats.parse(answer(cpu: ",\"frequency_mhz\":{\"average\":0.0,\"max\":0.0},\"temperature_celsius\":0.0"))
        XCTAssertNil(broken.cpu.frequencyMhz)
        XCTAssertNil(broken.cpu.temperatureCelsius)
        let absurd = try MachineStats.parse(answer(cpu: ",\"frequency_mhz\":{\"average\":99999.0,\"max\":99999.0},\"temperature_celsius\":900.0"))
        XCTAssertNil(absurd.cpu.frequencyMhz)
        XCTAssertNil(absurd.cpu.temperatureCelsius)
    }

    func testDiskSpeedThatIsNegativeIsDropped() throws {
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"disk_io\":{\"read_bytes_per_second\":-5.0,\"write_bytes_per_second\":1.0}")).diskIo)
    }

    func testCountsOutOfRangeAreDropped() throws {
        let stats = try MachineStats.parse(answer(network: ",\"errors_in_total\":-1,\"drops_in_total\":9999999999999999", top: ",\"process_count\":99999999999", process: ",\"threads\":0"))
        XCTAssertNil(stats.network.errorsInTotal)
        XCTAssertNil(stats.network.dropsInTotal)
        XCTAssertNil(stats.processCount)
        XCTAssertNil(stats.processes[0].threads, "a program has at least one thread; 0 means the helper did not know")
    }

    func testTheWrongTypeForAnExtraRefusesTheWholeAnswerLikeAnyOtherField() {
        XCTAssertThrowsError(try MachineStats.parse(answer(cpu: ",\"physical_cores\":\"many\"")))
    }
}
