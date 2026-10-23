import XCTest
@testable import AgentCore

final class CpuBrandTests: XCTestCase {
    private func answering(_ text: String) -> CpuBrand.Run {
        { _, _ in Data(text.utf8) }
    }

    func testTheBrandStringOfAnAppleChipIsRead() async {
        let asked = Asked()
        let name = await CpuBrand.read { executable, arguments in
            asked.set(executable, arguments)
            return Data("Apple M4\n".utf8)
        }
        XCTAssertEqual(name, "Apple M4")
        XCTAssertEqual(asked.executable, "/usr/sbin/sysctl")
        XCTAssertEqual(asked.arguments, ["-n", "machdep.cpu.brand_string"])
    }

    func testAnIntelMacNameIsTidied() async {
        let name = await CpuBrand.read(run: answering("Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz\n"))
        XCTAssertEqual(name, "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz")
    }

    func testControlCharactersAreDroppedSpacesCollapsedAndLongNamesCut() async {
        let messy = await CpuBrand.read(run: answering("  Apple\t M4 \u{0}\u{1B}Pro  \n"))
        XCTAssertEqual(messy, "Apple M4 Pro")
        let long = await CpuBrand.read(run: answering(String(repeating: "A", count: 300)))
        XCTAssertEqual(long?.count, CpuBrand.maxLength)
    }

    func testAnEmptyAnswerOrAFailedCommandGivesNil() async {
        let empty = await CpuBrand.read(run: answering(" \n"))
        XCTAssertNil(empty)
        let failed = await CpuBrand.read { _, _ in throw CocoaError(.fileNoSuchFile) }
        XCTAssertNil(failed)
    }

    func testTheNameIsInTheFactsWhenKnownAndLeftOutWhenNot() throws {
        func json(_ model: String?) throws -> [String: Any] {
            let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, cpuModel: model, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
            let facts = Facts(specs: specs, freeRamMb: 1, freeDiskGb: 1, capabilities: Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false),
                                     agentVersion: "0.1.0", engine: EngineInfo(identity: EngineIdentity(name: "apple-container", version: nil), ready: true))
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            return try JSONSerialization.jsonObject(with: encoder.encode(facts)) as! [String: Any]
        }
        XCTAssertEqual(try json("Apple M4")["cpu_model"] as? String, "Apple M4")
        XCTAssertNil(try json(nil)["cpu_model"])
    }
}

private final class Asked: @unchecked Sendable {
    private(set) var executable = ""
    private(set) var arguments: [String] = []
    func set(_ executable: String, _ arguments: [String]) { self.executable = executable; self.arguments = arguments }
}
