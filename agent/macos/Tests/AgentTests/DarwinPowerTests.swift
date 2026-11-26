import XCTest
@testable import Agent

final class DarwinPowerTests: XCTestCase {
    // A real powermetrics sample (Apple Silicon, passwordless sudo on the Mini).
    private static let sample = """
        Machine Model: Macmini9,1
        OS version: 24F74
        *** Sampled system activity (Thu Nov 26 12:00:00 2026 +0100) (200.00ms elapsed) ***
        CPU Power: 102 mW / GPU Power: 0 mW / ANE Power: 0 mW / Combined Power (CPU + GPU + ANE): 102 mW
        *** End of sample ***
        """

    func testParseTurnsMilliwattsIntoWattsOnOneDecimal() {
        XCTAssertEqual(DarwinPower.watts(sampleText: Self.sample), 0.1)
        let kiloScale = "CPU Power: 100 mW / GPU Power: 1000 mW / ANE Power: 45 mW / Combined Power (CPU + GPU + ANE): 12345 mW"
        XCTAssertEqual(DarwinPower.watts(sampleText: kiloScale), 12.3)
    }

    func testGarbageOrEmptyOrMissingCombinedLineGivesNil() {
        XCTAssertNil(DarwinPower.watts(sampleText: ""))
        XCTAssertNil(DarwinPower.watts(sampleText: "CPU Power: 102 mW / GPU Power: 0 mW"))
        XCTAssertNil(DarwinPower.watts(sampleText: "Combined Power (CPU + GPU + ANE): not-a-number mW"))
    }
}
