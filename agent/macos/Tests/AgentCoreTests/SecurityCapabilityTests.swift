import XCTest
@testable import AgentCore

final class SecurityCapabilityTests: XCTestCase {
    private func capabilitiesJson(_ capabilities: Capabilities) throws -> [String: Any] {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        let facts = Facts(specs: specs, freeRamMb: 1, freeDiskGb: 1, capabilities: capabilities, agentVersion: "0.1.0", engine: EngineInfo(identity: EngineIdentity(name: "apple-container", version: nil), ready: true))
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(facts)) as! [String: Any]
        return json["capabilities"] as! [String: Any]
    }

    func testTheFactsSayThisHelperServesSecurity() throws {
        let json = try capabilitiesJson(Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false))
        XCTAssertEqual(json["security"] as? Bool, true)
        XCTAssertEqual(Set(json.keys), ["vm", "container", "gpu_in_vm", "gpu_in_container", "security"])
    }

    func testEveryEngineReportsIt() {
        XCTAssertTrue(UnavailableEngine(name: "x", problem: HostProblem(code: "c", message: "m", fix: "f")).capabilities.security)
        XCTAssertTrue(SimulatedEngine().capabilities.security)
    }
}
