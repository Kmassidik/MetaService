import XCTest
@testable import AgentCore

final class AgentBuildTests: XCTestCase {
    private var folder: String!

    override func setUpWithError() throws {
        folder = NSTemporaryDirectory() + "ms-build-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: folder) }

    func testTheBuildIsTheLowercaseHexSha256OfTheFile() throws {
        let path = folder + "/program"
        try Data("abc".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(AgentBuild.sha256(ofFileAt: path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testAFileThatCannotBeReadHasNoBuild() {
        XCTAssertNil(AgentBuild.sha256(ofFileAt: folder + "/nothing"))
        XCTAssertNil(AgentBuild.sha256(ofFileAt: folder))
    }

    func testTheRunningProgramHasABuildThatStaysTheSame() throws {
        let first = try XCTUnwrap(AgentBuild.ofRunningProgram())
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(first, AgentBuild.ofRunningProgram())
    }

    func testTheFactsCarryTheBuildOnlyWhenThereIsOne() throws {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        func keys(_ build: String?) throws -> [String: Any] {
            let facts = Facts(specs: specs, freeRamMb: 1, freeDiskGb: 2, capabilities: Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false),
                              agentVersion: "0.1.0", engine: EngineInfo(identity: EngineIdentity(name: "simulated", version: nil), ready: true), agentBuild: build)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(facts)) as? [String: Any])
        }
        XCTAssertNil(try keys(nil)["agent_build"])
        XCTAssertEqual(try keys(String(repeating: "ab", count: 32))["agent_build"] as? String, String(repeating: "ab", count: 32))
    }

    func testTheServiceReportsItsBuildInTheFactsAndSaysNothingWhenItHasNone() async throws {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        let engine = SimulatedEngine()
        let build = String(repeating: "cd", count: 32)
        let with = AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9", agentBuild: build)
        let without = AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9")
        let reported = try await with.facts().agentBuild
        let silent = try await without.facts().agentBuild
        XCTAssertEqual(reported, build)
        XCTAssertNil(silent)
    }
}
