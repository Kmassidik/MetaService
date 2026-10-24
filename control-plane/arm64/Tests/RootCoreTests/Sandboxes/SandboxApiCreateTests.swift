import Foundation
import XCTest
@testable import RootCore

final class SandboxApiCreateTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    private let spec = SandboxCreateSpec(template: "base", timeoutSeconds: 300, envVars: [:])
    private let fullLimits = TeamLimits(maxRunning: 10, maxVcpu: 32, maxRamMb: 65_536, maxSandboxesPerHour: 60)
    private let emptyUsage = TeamUsage(running: 0, vcpu: 0, ramMb: 0, createdLastHour: 0)

    private let roomy = SandboxMachine(
        id: "pc", online: true,
        capabilities: Capabilities(vm: true, container: true, gpuInVm: false, gpuInContainer: false, sandbox: true),
        facts: SandboxFacts(engine: .init(name: "simulated", version: nil), maxRunning: 4, running: 0, paused: 0,
                            maxVcpu: 8, maxRamMb: 16_384, maxDiskMb: 102_400,
                            booked: .init(vcpu: 0, ramMb: 0, diskMb: 0),
                            templates: [.init(id: "base", build: "b1", ready: true)], changes: 0))

    private func failure(_ limits: TeamLimits = TeamLimits(maxRunning: 10, maxVcpu: 32, maxRamMb: 65_536, maxSandboxesPerHour: 60),
                         usage: TeamUsage = TeamUsage(running: 0, vcpu: 0, ramMb: 0, createdLastHour: 0),
                         machines: [SandboxMachine]? = nil, spec: SandboxCreateSpec? = nil) -> SandboxApiFailure? {
        do {
            _ = try SandboxApiCreate.plan(spec: spec ?? self.spec, limits: limits, usage: usage,
                                          machines: machines ?? [roomy], createdAt: createdAt, id: "aaaaaaaaaaaaaaaaaaaa")
            return nil
        } catch let failure as SandboxApiFailure {
            return failure
        } catch {
            return nil
        }
    }

    func testAPlanNamesTheMachineAndTheEndTime() throws {
        let plan = try SandboxApiCreate.plan(spec: spec, limits: fullLimits, usage: emptyUsage, machines: [roomy],
                                             createdAt: createdAt, id: "aaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(plan.id, "aaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(plan.machine, "pc")
        XCTAssertEqual(plan.template, "base")
        XCTAssertEqual(plan.endAt, createdAt.addingTimeInterval(300))
        XCTAssertEqual(plan.shape, SandboxShape())
    }

    /// The order is the point: a team over its limit is refused before any machine is even looked at, so nothing can be started.
    func testALimitRefusalComesBeforePlacement() {
        let used = TeamUsage(running: 1, vcpu: 2, ramMb: 512, createdLastHour: 1)
        let answer = failure(TeamLimits(maxRunning: 1, maxVcpu: 32, maxRamMb: 65_536, maxSandboxesPerHour: 60),
                             usage: used, machines: [])
        XCTAssertEqual(answer?.status, 429)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.teamLimit)
    }

    func testASizeRefusalIs403AndAnHourlyOneIs429() {
        let busy = TeamUsage(running: 0, vcpu: 8, ramMb: 8_000, createdLastHour: 0)
        XCTAssertEqual(failure(TeamLimits(maxRunning: 10, maxVcpu: 8, maxRamMb: 65_536, maxSandboxesPerHour: 60), usage: busy)?.status, 403)
        let hourly = TeamUsage(running: 0, vcpu: 0, ramMb: 0, createdLastHour: 60)
        XCTAssertEqual(failure(TeamLimits(maxRunning: 10, maxVcpu: 32, maxRamMb: 65_536, maxSandboxesPerHour: 60), usage: hourly)?.status, 429)
    }

    func testNoSandboxMachineIs503() {
        let answer = failure(machines: [])
        XCTAssertEqual(answer?.status, 503)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.noRoom)
    }

    func testAnOfflineMachineIs503() {
        let offline = SandboxMachine(id: "pc", online: false, capabilities: roomy.capabilities, facts: roomy.facts)
        XCTAssertEqual(failure(machines: [offline])?.status, 503)
    }

    func testATimeoutPastTheTeamLifeIsA403() {
        let tooLong = SandboxCreateSpec(template: "base", timeoutSeconds: SandboxEndTime.maximumLifeSeconds + 1, envVars: [:])
        let answer = failure(spec: tooLong)
        XCTAssertEqual(answer?.status, 403)
        XCTAssertEqual(answer?.errorCode, SandboxApiCodes.teamLimit)
    }
}
