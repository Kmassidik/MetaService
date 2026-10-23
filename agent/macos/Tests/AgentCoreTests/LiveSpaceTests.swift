import XCTest
@testable import AgentCore

/// The budget follows the machine: a volume can grow or shrink while the Agent runs.
final class LiveSpaceTests: XCTestCase {
    private let ram = 65536

    private func reading(ram: Int? = nil, disk: Int) -> MachineReading {
        MachineReading(ramTotalMb: ram ?? self.ram, diskTotalGb: disk, diskAvailableGb: disk / 2)
    }

    private func workload(disk: Int, state: WorkloadState) -> Workload {
        Workload(id: "w", name: "n", kind: .vm, state: state, cpu: 1, ramMb: 1024, diskGb: disk, gpuMode: .none)
    }

    func testDiskTotalFollowsAVolumeThatGrewWhileRunning() {
        let start = SpaceBudget(ramTotalMb: ram, diskTotalGb: 105)
        XCTAssertEqual([start.reserveDiskGb, start.freeDiskGb(workloads: [])], [30, 55])
        let grown = start.after(reading(disk: 981))
        XCTAssertEqual([grown.diskTotalGb, grown.reserveDiskGb], [981, 196])
        XCTAssertEqual(grown.freeDiskGb(workloads: []), 981 - 196 - 20)
        let held = [workload(disk: 50, state: .running), workload(disk: 30, state: .stopped)]
        XCTAssertEqual(grown.freeDiskGb(workloads: held), 981 - 196 - 20 - 80, "a stopped workload still holds its disk")
    }

    func testRamTotalFollowsTheSameWay() {
        let grown = SpaceBudget(ramTotalMb: 16384, diskTotalGb: 500).after(reading(ram: 65536, disk: 500))
        XCTAssertEqual([grown.ramTotalMb, grown.reserveRamMb], [65536, 16384])
    }

    func testAnExplicitAllowanceIsKeptAndClampedToTheNewTotal() {
        let set = SpaceBudget(ramTotalMb: ram, diskTotalGb: 105, diskAllowanceGb: 300)
        XCTAssertEqual(set.after(reading(disk: 981)).freeDiskGb(workloads: []), 300 - 196 - 20)
        XCTAssertEqual(set.after(reading(disk: 200)).freeDiskGb(workloads: []), 200 - 40 - 20, "the allowance cannot exceed the new total")
    }

    func testAnExplicitReserveStaysWhileADefaultOneMoves() {
        let pinned = SpaceBudget(ramTotalMb: ram, diskTotalGb: 105, reserveRamMb: 5000, reserveDiskGb: 77)
        let grown = pinned.after(reading(ram: 131072, disk: 981))
        XCTAssertEqual([grown.reserveDiskGb, grown.reserveRamMb], [77, 5000])
        let half = SpaceBudget(ramTotalMb: ram, diskTotalGb: 105, reserveDiskGb: 77).after(reading(ram: 131072, disk: 981))
        XCTAssertEqual([half.reserveDiskGb, half.reserveRamMb], [77, 32768])
    }

    func testAFailedReadKeepsTheLastGoodNumbers() {
        let start = SpaceBudget(ramTotalMb: ram, diskTotalGb: 981)
        for bad in [nil, reading(ram: 0, disk: 981), reading(disk: 0), reading(ram: 0, disk: 0)] {
            XCTAssertEqual(start.after(bad), start)
        }
    }
}

/// The facts a heartbeat sends and the create check follow the machine as it is now.
final class LiveSpaceServiceTests: XCTestCase {
    private final class Machine: @unchecked Sendable {
        private let lock = NSLock()
        private var current: MachineReading
        init(disk: Int) { current = Machine.reading(disk) }
        private static func reading(_ disk: Int) -> MachineReading { MachineReading(ramTotalMb: 65536, diskTotalGb: disk, diskAvailableGb: disk) }
        func set(disk: Int) { lock.lock(); current = Machine.reading(disk); lock.unlock() }
        func read() -> MachineReading { lock.lock(); defer { lock.unlock() }; return current }
    }

    private func service(over machine: Machine) -> AgentService {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 8, ramTotalMb: 65536, diskTotalGb: 105, gpu: [])
        return AgentService(engine: SimulatedEngine(), budget: SpaceBudget(ramTotalMb: 65536, diskTotalGb: 105), specs: specs, agentVersion: "0.9.9", readMachine: { machine.read() })
    }

    func testTwoHeartbeatsReportTheVolumeBeforeAndAfterItGrew() async throws {
        let machine = Machine(disk: 105)
        let service = service(over: machine)
        let before = try await service.facts()
        XCTAssertEqual([before.specs.diskTotalGb, before.freeDiskGb], [105, 55])
        machine.set(disk: 981)
        let after = try await service.facts()
        XCTAssertEqual([after.specs.diskTotalGb, after.freeDiskGb], [981, 981 - 196 - 20])
    }
}
