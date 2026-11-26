import XCTest
@testable import RootCore

/// The power input's volts, amps and watts: kept when in range, left out (never clamped, never 0) when not said or absurd.
final class MachineStatsPowerInputTests: XCTestCase {
    private func answer(top extraTop: String = "") -> Data {
        Data("""
        {"taken_at":"2026-10-21T10:00:00Z","measuring":false,"uptime_seconds":5,
         "cpu":{"core_count":4,"total_percent":1.5,"cores_percent":[1.0,2.0,3.0,4.0],"load":{"one":1.0,"five":null,"fifteen":0.5}},
         "memory":{"total_bytes":100,"used_bytes":40,"cached_bytes":20,"free_bytes":40,"swap_total_bytes":0,"swap_used_bytes":0},
         "disks":[],
         "network":{"received_total_bytes":1,"sent_total_bytes":2,"received_bytes_per_second":3.0,"sent_bytes_per_second":4.0},
         "processes":[]\(extraTop)}
        """.utf8)
    }

    func testInputFieldsAreKeptWhenInRange() throws {
        let stats = try MachineStats.parse(answer(top: ",\"input_voltage\":12.6,\"input_current\":2.75,\"input_watts\":34.7"))
        XCTAssertEqual(stats.inputVoltage, 12.6)
        XCTAssertEqual(stats.inputCurrent, 2.75)
        XCTAssertEqual(stats.inputWatts, 34.7)
        let text = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        for key in ["inputVoltage", "inputCurrent", "inputWatts"] {
            XCTAssertTrue(text.contains(key), "\(key) in \(text)")
        }
    }

    func testInputFieldsOutOfRangeAreDroppedNotClamped() throws {
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"input_voltage\":400.0")).inputVoltage, "past maxInputVoltage")
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"input_current\":25.0")).inputCurrent, "past maxInputAmperes")
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"input_watts\":9999.0")).inputWatts, "past maxInputWatts")
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"input_voltage\":-5.0")).inputVoltage, "negative")
        XCTAssertNil(try MachineStats.parse(answer(top: ",\"input_current\":null")).inputCurrent)
    }

    func testAWrongTypedInputReadsAsNotSaidNotARefusedAnswer() throws {
        let stats = try MachineStats.parse(answer(top: ",\"input_voltage\":\"mains\",\"input_watts\":\"plenty\""))
        XCTAssertNil(stats.inputVoltage)
        XCTAssertNil(stats.inputWatts)
    }

    func testUnknownInputStaysOutOfTheAnswer() throws {
        let stats = try MachineStats.parse(answer())
        XCTAssertNil(stats.inputVoltage)
        XCTAssertNil(stats.inputCurrent)
        XCTAssertNil(stats.inputWatts)
        let text = String(decoding: try JSONEncoder().encode(stats), as: UTF8.self)
        for key in ["inputVoltage", "inputCurrent", "inputWatts"] {
            XCTAssertFalse(text.contains(key), "\(key) must stay out of the answer")
        }
    }
}
