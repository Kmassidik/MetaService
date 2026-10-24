import XCTest
@testable import RootCore

final class SandboxPlacementTests: XCTestCase {
    private let shape = SandboxShape(vcpu: 2, ramMb: 512, diskMb: 1_024)

    private func capabilities(sandbox: Bool = true) -> Capabilities {
        Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false, sandbox: sandbox)
    }

    private func facts(running: Int = 0, maxRunning: Int = 10, vcpu: Int = 0, ramMb: Int = 0, diskMb: Int = 0,
                       maxVcpu: Int = 8, maxRamMb: Int = 8_192, maxDiskMb: Int = 10_240) -> SandboxFacts {
        SandboxFacts(engine: .init(name: "firecracker", version: "1.10.1"), maxRunning: maxRunning, running: running, paused: 0, maxVcpu: maxVcpu,
                     maxRamMb: maxRamMb, maxDiskMb: maxDiskMb, booked: .init(vcpu: vcpu, ramMb: ramMb, diskMb: diskMb), templates: [], changes: 0)
    }

    private func machine(_ id: String, online: Bool = true, sandbox: Bool = true, _ facts: SandboxFacts?) -> SandboxMachine {
        SandboxMachine(id: id, online: online, capabilities: capabilities(sandbox: sandbox), facts: facts)
    }

    func testTheLeastBookedMachineWins() throws {
        let busy = machine("busy", facts(running: 1, vcpu: 4, ramMb: 4_096, diskMb: 5_000))
        let quiet = machine("quiet", facts(vcpu: 1, ramMb: 512, diskMb: 1_000))
        XCTAssertEqual(try SandboxPlacement.choose([busy, quiet], shape: shape), "quiet")
        XCTAssertEqual(try SandboxPlacement.choose([quiet, busy], shape: shape), "quiet")
    }

    func testAnEqualBookedPairIsBrokenByTheLowerId() throws {
        let one = machine("b", facts(vcpu: 1, ramMb: 1_024))
        let two = machine("a", facts(vcpu: 1, ramMb: 1_024))
        XCTAssertEqual(try SandboxPlacement.choose([one, two], shape: shape), "a")
        XCTAssertEqual(try SandboxPlacement.choose([two, one], shape: shape), "a")
    }

    func testAnEqualMemoryPairGoesToTheLowerVcpu() throws {
        let wide = machine("wide", facts(vcpu: 4, ramMb: 1_024))
        let narrow = machine("narrow", facts(vcpu: 1, ramMb: 1_024))
        XCTAssertEqual(try SandboxPlacement.choose([wide, narrow], shape: shape), "narrow")
    }

    func testAMachineWithoutSandboxSupportOrFactsIsNeverPicked() throws {
        let listed = machine("listed", sandbox: false, facts())
        let silent = machine("silent", nil)
        let good = machine("good", facts())
        XCTAssertEqual(try SandboxPlacement.choose([listed, silent, good], shape: shape), "good")
    }

    func testNoCapableMachineIsItsOwnRefusal() {
        let machines = [machine("old", sandbox: false, facts()), machine("silent", nil)]
        XCTAssertThrowsError(try SandboxPlacement.choose(machines, shape: shape)) {
            XCTAssertEqual(($0 as? SandboxPlacementRefusal)?.code, SandboxPlacement.noSandboxMachineCode)
        }
    }

    func testASandboxMachineThatIsOfflineIsItsOwnRefusal() {
        XCTAssertThrowsError(try SandboxPlacement.choose([machine("off", online: false, facts())], shape: shape)) {
            XCTAssertEqual(($0 as? SandboxPlacementRefusal)?.code, SandboxPlacement.noMachineOnlineCode)
        }
    }

    func testAFullMachineHasNoRoomForOneMore() {
        let full = machine("full", facts(running: 2, maxRunning: 2, maxVcpu: 64, maxRamMb: 65_536, maxDiskMb: 100_000))
        XCTAssertThrowsError(try SandboxPlacement.choose([full], shape: shape)) {
            let refusal = $0 as? SandboxPlacementRefusal
            XCTAssertEqual(refusal?.code, SandboxPlacement.noRoomCode)
            XCTAssertEqual(refusal?.resource, SandboxPlacement.slotsResource)
            XCTAssertEqual(refusal?.free, 0)
        }
    }

    func testAShortageNamesTheResourceAndTheNumbers() {
        let cpuShort = machine("cpu", facts(maxVcpu: 1))
        XCTAssertThrowsError(try SandboxPlacement.choose([cpuShort], shape: shape)) {
            let refusal = $0 as? SandboxPlacementRefusal
            XCTAssertEqual(refusal?.resource, SandboxPlacement.vcpuResource)
            XCTAssertEqual(refusal?.needed, 2)
            XCTAssertEqual(refusal?.free, 1)
        }
        let ramShort = machine("ram", facts(maxRamMb: 256))
        XCTAssertThrowsError(try SandboxPlacement.choose([ramShort], shape: shape)) {
            XCTAssertEqual(($0 as? SandboxPlacementRefusal)?.resource, SandboxPlacement.ramResource)
        }
        let diskShort = machine("disk", facts(diskMb: 1, maxDiskMb: 1_024))
        XCTAssertThrowsError(try SandboxPlacement.choose([diskShort], shape: shape)) {
            XCTAssertEqual(($0 as? SandboxPlacementRefusal)?.resource, SandboxPlacement.diskResource)
        }
    }

    func testAShapeThatFitsExactlyIsPlaced() throws {
        let exact = machine("exact", facts(maxVcpu: 2, maxRamMb: 512, maxDiskMb: 1_024))
        XCTAssertEqual(try SandboxPlacement.choose([exact], shape: shape), "exact")
    }

    func testAMachineThatIsFullIsSkippedForOneWithRoom() throws {
        let full = machine("full", facts(running: 1, maxRunning: 1))
        let open = machine("open", facts(vcpu: 1, ramMb: 256))
        XCTAssertEqual(try SandboxPlacement.choose([full, open], shape: shape), "open")
    }

    func testASlotFullMachineDoesNotHideTheRealShortageElsewhere() {
        let full = machine("full", facts(running: 1, maxRunning: 1, maxVcpu: 64, maxRamMb: 65_536, maxDiskMb: 100_000))
        let tight = machine("tight", facts(maxRamMb: 256))
        XCTAssertThrowsError(try SandboxPlacement.choose([full, tight], shape: shape)) {
            XCTAssertEqual(($0 as? SandboxPlacementRefusal)?.resource, SandboxPlacement.ramResource)
        }
    }
}
