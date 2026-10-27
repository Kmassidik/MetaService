import XCTest
@testable import AgentCore

final class DeleteTests: XCTestCase {
    private let workloadId = "w-delete"

    private func service(_ engine: Engine) -> AgentService {
        let specs = MachineSpecs(os: "macos", arch: "arm64", cpuCores: 10, ramTotalMb: 32768, diskTotalGb: 1000, gpu: [])
        return AgentService(engine: engine, budget: SpaceBudget(ramTotalMb: 32768, diskTotalGb: 1000), specs: specs, agentVersion: "0.9.9")
    }

    private func runningEngine() async throws -> SimulatedEngine {
        let engine = SimulatedEngine()
        _ = try await engine.create(id: workloadId, request: request())
        return engine
    }

    private func request() throws -> CreateWorkloadRequest {
        let body = try JSONSerialization.data(withJSONObject: ["command_id": "create-delete", "name": "demo", "kind": "vm", "cpu": 1, "ram_mb": 512, "disk_gb": 1])
        return try CreateWorkloadRequest(body: body)
    }

    func testRunningWorkloadStopsBeforeBackupAndIsDeleted() async throws {
        let engine = try await runningEngine()
        let agent = service(engine)

        _ = try await agent.delete(commandId: "delete-running", id: workloadId)
        let done = try await finished(agent, "delete-running")

        let operations = await engine.lifecycleOperations
        let remaining = try await engine.list()
        XCTAssertEqual(done.state, .succeeded)
        XCTAssertEqual(done.result?["backup_id"], "backup-\(workloadId)")
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)", "delete:\(workloadId)"])
        XCTAssertEqual(remaining, [])
    }

    func testStoppedWorkloadIsBackedUpWithoutAnotherStopOrAStart() async throws {
        let engine = try await runningEngine()
        try await engine.setRunning(id: workloadId, running: false)
        let agent = service(engine)

        _ = try await agent.delete(commandId: "delete-stopped", id: workloadId)
        let done = try await finished(agent, "delete-stopped")

        let operations = await engine.lifecycleOperations
        XCTAssertEqual(done.state, .succeeded)
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)", "delete:\(workloadId)"])
    }

    func testBackupFailureRestartsRunningWorkloadAndReportsActualReason() async throws {
        let engine = try await runningEngine()
        await engine.failBackups(.failed("container export: container is not stopped"))
        let agent = service(engine)

        _ = try await agent.delete(commandId: "backup-fails", id: workloadId)
        let done = try await finished(agent, "backup-fails", wanting: .failed)

        let operations = await engine.lifecycleOperations
        let state = try await engine.list().first?.state
        XCTAssertEqual(done.result?["error"], "container export: container is not stopped")
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)", "start:\(workloadId)"])
        XCTAssertEqual(state, .running)
    }

    func testDeleteFailureRestartsRunningWorkloadAndReportsActualReason() async throws {
        let engine = try await runningEngine()
        await engine.failDeletes(.failed("container delete exited with 1: busy"))
        let agent = service(engine)

        _ = try await agent.delete(commandId: "delete-fails", id: workloadId)
        let done = try await finished(agent, "delete-fails", wanting: .failed)

        let operations = await engine.lifecycleOperations
        let state = try await engine.list().first?.state
        XCTAssertEqual(done.result?["error"], "container delete exited with 1: busy")
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)", "delete:\(workloadId)", "start:\(workloadId)"])
        XCTAssertEqual(state, .running)
    }

    func testFailureDoesNotRestartAWorkloadThatWasAlreadyStopped() async throws {
        let engine = try await runningEngine()
        try await engine.setRunning(id: workloadId, running: false)
        await engine.failBackups(.failed("export failed"))
        let agent = service(engine)

        _ = try await agent.delete(commandId: "stopped-backup-fails", id: workloadId)
        _ = try await finished(agent, "stopped-backup-fails", wanting: .failed)

        let operations = await engine.lifecycleOperations
        let state = try await engine.list().first?.state
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)"])
        XCTAssertEqual(state, .stopped)
    }

    func testDeleteAcceptanceNotifiesAndExposesDeletingState() async throws {
        let engine = try await runningEngine()
        await engine.delayBackups(nanoseconds: 100_000_000)
        let agent = service(engine)
        let changes = ChangeCounter()
        agent.onChange = { changes.increment() }

        let accepted = try await agent.delete(commandId: "delete-visible", id: workloadId)

        let visibleState = try await agent.workloads().first?.state
        XCTAssertEqual(accepted.state, .running)
        XCTAssertEqual(changes.value, 1)
        XCTAssertEqual(visibleState, .deleting)
        _ = try await finished(agent, "delete-visible")
        XCTAssertEqual(changes.value, 2)
    }

    func testDeleteCommandsCoalescePerWorkloadAndSameIdReturnsExisting() async throws {
        let engine = try await runningEngine()
        await engine.delayDeletes(nanoseconds: 100_000_000)
        let agent = service(engine)

        let first = try await agent.delete(commandId: "delete-owner", id: workloadId)
        let retry = try await agent.delete(commandId: "delete-retry", id: workloadId)
        let repeated = try await agent.delete(commandId: "delete-owner", id: workloadId)

        XCTAssertEqual(first, retry)
        XCTAssertEqual(first, repeated)
        _ = try await finished(agent, "delete-owner")
        let operations = await engine.lifecycleOperations
        XCTAssertEqual(operations, ["stop:\(workloadId)", "backup:\(workloadId)", "delete:\(workloadId)"])
        let existing = try await agent.delete(commandId: "delete-owner", id: workloadId)
        XCTAssertEqual(existing.state, .succeeded)
    }

    func testRestartFailureIsIncludedInTheDeleteError() async throws {
        let engine = try await runningEngine()
        await engine.failBackups(.failed("export failed"))
        await engine.failRestarts(.failed("start failed"))
        let agent = service(engine)

        _ = try await agent.delete(commandId: "restart-fails", id: workloadId)
        let done = try await finished(agent, "restart-fails", wanting: .failed)

        XCTAssertEqual(done.result?["error"], "export failed (could not restart: start failed)")
        let state = try await engine.list().first?.state
        XCTAssertEqual(state, .stopped)
    }

    func testDeleteErrorIsReducedToOneLineAndThreeHundredUTF8Bytes() async throws {
        let engine = try await runningEngine()
        let reason = "export failed!\n" + String(repeating: "é", count: 200)
        await engine.failBackups(.failed(reason))
        let agent = service(engine)

        _ = try await agent.delete(commandId: "bounded-error", id: workloadId)
        let done = try await finished(agent, "bounded-error", wanting: .failed)
        let message = try XCTUnwrap(done.result?["error"])

        XCTAssertFalse(message.contains("\n"))
        XCTAssertTrue(message.hasPrefix("export failed! "))
        XCTAssertLessThanOrEqual(message.utf8.count, 300)
        XCTAssertEqual(message.utf8.count, 299)
    }

    private func finished(_ agent: AgentService, _ id: String, wanting: CommandState = .succeeded) async throws -> Command {
        for _ in 0..<200 {
            let command = try await agent.command(id)
            if command.state == wanting { return command }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw EngineError.failed("the command did not finish")
    }
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}
