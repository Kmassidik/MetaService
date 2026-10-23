import XCTest
@testable import RootCore

final class TerminalSupportTests: XCTestCase {
    private func capabilities(terminal: Bool) -> Capabilities {
        Capabilities(vm: false, container: true, gpuInVm: false, gpuInContainer: false, terminal: terminal)
    }

    func testAMachineThatSaysTerminalHasAConsoleOnAnySystem() {
        for os in ["linux", "macos", "windows"] { XCTAssertTrue(TerminalSupport.isSupported(machineOS: os, capabilities: capabilities(terminal: true)), os) }
    }

    func testAMacKeepsItsConsoleBeforeItsHelperIsUpdated() {
        XCTAssertTrue(TerminalSupport.isSupported(machineOS: "macos", capabilities: capabilities(terminal: false)))
        XCTAssertTrue(TerminalSupport.isSupported(machineOS: "macos", capabilities: nil))
    }

    func testALinuxHelperWithoutTheFlagMustBeUpdated() {
        XCTAssertFalse(TerminalSupport.isSupported(machineOS: "linux", capabilities: capabilities(terminal: false)))
        XCTAssertFalse(TerminalSupport.isSupported(machineOS: "linux", capabilities: nil))
        for other in ["windows", "", "Darwin", "MACOS"] { XCTAssertFalse(TerminalSupport.isSupported(machineOS: other, capabilities: nil), other) }
    }

    func testTheRefusalSaysToUpdateTheHelper() {
        XCTAssertEqual(TerminalSupport.message, "Update the helper on this machine to use the terminal.")
    }

    func testCapabilitiesSavedBeforeTheFlagReadAsFalse() throws {
        let old = Data(#"{"vm":true,"container":true,"gpuInVm":false,"gpuInContainer":false}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Capabilities.self, from: old).terminal)
        let flagged = Data(#"{"vm":true,"container":true,"gpuInVm":false,"gpuInContainer":false,"terminal":true}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Capabilities.self, from: flagged).terminal)
    }
}
