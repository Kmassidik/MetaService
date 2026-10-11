import XCTest
@testable import RootCore

final class ComputerChecksTests: XCTestCase {
    private func run(agent: Bool = true, free: Int = 100, present: Set<String> = []) -> [String: Requirement] {
        Dictionary(uniqueKeysWithValues: ComputerChecks.run(agentReady: agent, freeDiskGb: free, exists: { present.contains($0) }).map { ($0.id, $0) })
    }

    func testAComputerWithEverythingPassesEveryCheck() {
        let all = run(present: ["/usr/local/bin/container", "/usr/bin/python3"])
        XCTAssertEqual(all.keys.sorted(), ["agent", "container", "disk", "python"])
        XCTAssertTrue(all.values.allSatisfy(\.ok), "\(all.values.filter { !$0.ok })")
    }

    func testAMissingContainerToolIsReportedAndDoesNotBlockTheInstall() {
        let found = run(present: ["/usr/bin/python3"])["container"]!
        XCTAssertFalse(found.ok)
        XCTAssertTrue(found.optional)
        XCTAssertTrue(found.detail.contains("cannot create VMs"))
    }

    func testTheToolIsFoundInAnyOfTheAgentsOwnPlaces() {
        for path in ComputerChecks.containerPaths { XCTAssertTrue(run(present: [path])["container"]!.ok, path) }
        XCTAssertTrue(run(present: ["/opt/homebrew/bin/container"])["container"]!.detail.contains("/opt/homebrew/bin/container"))
    }

    func testMissingPythonIsReported() {
        XCTAssertFalse(run()["python"]!.ok)
        for path in ComputerChecks.pythonPaths { XCTAssertTrue(run(present: [path])["python"]!.ok, path) }
    }

    func testTheMissingMetaServiceProgramIsTheOnlyCheckThatBlocks() {
        let nothing = run(agent: false, free: 1)
        XCTAssertEqual(nothing.values.filter { !$0.optional }.map(\.id), ["agent"])
        XCTAssertFalse(nothing["agent"]!.ok)
        XCTAssertTrue(nothing["agent"]!.detail.contains("./install.sh"))
    }

    func testTheDiskCheckSitsExactlyOnTheMinimum() {
        XCTAssertFalse(run(free: ComputerChecks.minimumFreeDiskGb - 1)["disk"]!.ok)
        XCTAssertTrue(run(free: ComputerChecks.minimumFreeDiskGb)["disk"]!.ok)
        XCTAssertTrue(run(free: 5)["disk"]!.detail.contains("at least \(ComputerChecks.minimumFreeDiskGb) GB"))
    }
}
