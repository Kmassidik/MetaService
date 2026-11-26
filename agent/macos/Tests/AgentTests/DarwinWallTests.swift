import XCTest
@testable import Agent

final class DarwinWallTests: XCTestCase {
    // A real ioreg sample (`ioreg -r -k PowerTelemetryData -d 1`, Mac mini M4, desktop AppleSmartBattery-compatible SMC node).
    // Proof of the unit math: 12.583 V × 2.75 A = 34.60 W ≈ SystemPowerIn 3467 × 0.01 W.
    private static let miniSample = """
        +-o AppleSMC  <class AppleSMC, id 0x100000abc, !registered, !matched, active, busy 0 (0 ms), retain 12>
              | "PowerTelemetryData" = {"AccumulatedWallEnergyEstimate"=729932084,"SystemEnergyConsumed"=0,"SystemPowerInAccumulatorCount"=120914,"SystemLoad"=7849,"AccumulatedSystemLoad"=3649870369,"SystemCurrentIn"=275,"AdapterEfficiencyLoss"=0,"WallEnergyEstimate"=0,"SystemLoadAccumulatorCount"=1447041,"AdapterEfficiencyLossAccumulatorCount"=103136,"SystemVoltageIn"=12583,"SystemPowerIn"=3467,"AccumulatedBatteryPower"=1172566250}
        """
    // A real sample from the old Mac Studio (M4 Max): 12.086 V × 5.66 A = 68.41 W ≈ 6843 × 0.01 W.
    private static let studioSample = """
        "PowerTelemetryData" = {"SystemCurrentIn"=566,"SystemVoltageIn"=12086,"SystemPowerIn"=6843}
        """

    func testParseTurnsMiniSampleIntoVoltsAmpsWatts() {
        XCTAssertEqual(DarwinWall.reading(sampleText: Self.miniSample),
                       DarwinWall.Reading(voltage: 12.6, current: 2.75, watts: 34.7))
    }

    func testParseTurnsStudioSampleIntoVoltsAmpsWatts() {
        XCTAssertEqual(DarwinWall.reading(sampleText: Self.studioSample),
                       DarwinWall.Reading(voltage: 12.1, current: 5.66, watts: 68.4))
    }

    func testMissingCurrentAndPowerGiveVoltageOnly() {
        let text = "\"PowerTelemetryData\" = {\"SystemVoltageIn\"=12052,\"SystemPowerInAccumulatorCount\"=120914}"
        XCTAssertEqual(DarwinWall.reading(sampleText: text), DarwinWall.Reading(voltage: 12.1, current: nil, watts: nil))
    }

    func testAllZeroTelemetryReadsAsUnknownNotZeros() {
        // Real behaviour: the node holds zeros until its first real update.
        let text = "\"PowerTelemetryData\" = {\"SystemCurrentIn\"=0,\"SystemVoltageIn\"=0,\"SystemPowerIn\"=0}"
        XCTAssertEqual(DarwinWall.reading(sampleText: text), .unknown)
    }

    func testGarbageOrEmptyGivesAllNil() {
        XCTAssertEqual(DarwinWall.reading(sampleText: ""), .unknown)
        XCTAssertEqual(DarwinWall.reading(sampleText: "hello world"), .unknown)
        XCTAssertEqual(DarwinWall.reading(sampleText: "\"SystemVoltageIn\"=not-a-number"), .unknown)
    }
}
