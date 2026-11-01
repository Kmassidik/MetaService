import XCTest
@testable import RootCore

/// Which machines the security puller asks. A machine with running VMs is busy, and busy machines must be asked too (the RTX PC and the Spark are busy while they run VMs).
final class SecurityWatchTests: XCTestCase {
    func testOnlineAndBusyMachinesThatServeSecurityAreAsked() {
        XCTAssertTrue(SecurityPuller.isWatched(state: "online", serves: true))
        XCTAssertTrue(SecurityPuller.isWatched(state: "busy", serves: true))
    }

    func testAnOfflineMachineIsNotAsked() {
        XCTAssertFalse(SecurityPuller.isWatched(state: "offline", serves: true))
    }

    func testAMachineWhoseHelperDoesNotServeSecurityIsNotAsked() {
        XCTAssertFalse(SecurityPuller.isWatched(state: "online", serves: false))
        XCTAssertFalse(SecurityPuller.isWatched(state: "busy", serves: nil))
    }
}
