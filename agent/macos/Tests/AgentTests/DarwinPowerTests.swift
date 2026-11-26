import XCTest
@testable import Agent

final class DarwinPowerTests: XCTestCase {
    // A real powermetrics sample (Apple Silicon, passwordless sudo on the Mini, cpu_power and gpu_power samplers).
    // The gpu_power sampler repeats the GPU Power line; only the first occurrence counts.
    private static let sample = """
        Machine Model: Macmini9,1
        OS version: 24F74
        *** Sampled system activity (Thu Nov 26 12:00:00 2026 +0100) (200.00ms elapsed) ***
        CPU Power: 12340 mW
        GPU Power: 0 mW
        ANE Power: 0 mW
        Combined Power (CPU + GPU + ANE): 12340 mW
        *** End of sample ***
        """

    private static let gpuSamplerTail = """
        GPU Power: 999 mW
        *** End of sample ***
        """

    func testParseTurnsMilliwattsIntoWattsOnOneDecimal() {
        XCTAssertEqual(DarwinPower.readings(sampleText: Self.sample + Self.gpuSamplerTail),
                       DarwinPower.Reading(combined: 12.3, cpu: 12.3, gpu: 0, ane: 0))
        let kiloScale = "CPU Power: 100 mW\nGPU Power: 1000 mW\nANE Power: 45 mW\nCombined Power (CPU + GPU + ANE): 12345 mW"
        XCTAssertEqual(DarwinPower.readings(sampleText: kiloScale),
                       DarwinPower.Reading(combined: 12.3, cpu: 0.1, gpu: 1, ane: 0))
    }

    func testParseIsCaseInsensitive() {
        let text = "cpu power: 100 mW\ngpu power: 0 mW\nane power: 0 mW\ncombined power (CPU + GPU + ANE): 100 mW"
        XCTAssertEqual(DarwinPower.readings(sampleText: text), DarwinPower.Reading(combined: 0.1, cpu: 0.1, gpu: 0, ane: 0))
    }

    func testMissingAneLineGivesNilForAneOnly() {
        let text = "CPU Power: 100 mW\nGPU Power: 0 mW\nCombined Power (CPU + GPU + ANE): 100 mW"
        XCTAssertEqual(DarwinPower.readings(sampleText: text), DarwinPower.Reading(combined: 0.1, cpu: 0.1, gpu: 0, ane: nil))
    }

    func testGarbageOrEmptyOrMissingLinesGiveAllNil() {
        XCTAssertEqual(DarwinPower.readings(sampleText: ""), .unknown)
        XCTAssertEqual(DarwinPower.readings(sampleText: "CPU Power: 102 mW / GPU Power: 0 mW"), DarwinPower.Reading(combined: nil, cpu: 0.1, gpu: 0, ane: nil))
        XCTAssertEqual(DarwinPower.readings(sampleText: "Combined Power (CPU + GPU + ANE): not-a-number mW"), .unknown)
        XCTAssertEqual(DarwinPower.readings(sampleText: "hello world"), .unknown)
    }
}
