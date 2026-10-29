import XCTest
import AgentCore
@testable import Agent

final class ExternalServicesTests: XCTestCase {
    func testDockerParsingUsesFullIdsAndReadOnlyArgv() async throws {
        let id = String(repeating: "a", count: 64)
        let cli = ExternalStubCLI(results: [.success(Data("{\"ID\":\"\(id)\",\"Names\":\"web\",\"Image\":\"nginx:1.27\",\"State\":\"running\"}\n{\"ID\":\"beef\",\"Names\":\"old\",\"State\":\"exited\"}\n".utf8))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: CommandLedger())

        let result = await service.list()

        XCTAssertEqual(result.services, [ExternalService(id: "docker:beef", name: "old", runtime: .docker, kind: .container, state: .stopped, image: nil),
                                         ExternalService(id: "docker:\(id)", name: "web", runtime: .docker, kind: .container, state: .running, image: "nginx:1.27")])
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(cli.calls, [ExternalCall(arguments: ["ps", "--all", "--no-trunc", "--format", "{{json .}}"], timeout: 30)])
    }

    func testAppleParsingExcludesOnlyPersistedManagedVms() async throws {
        let json = #"""
        [
          {"id":"11111111-1111-1111-1111-111111111111","configuration":{"id":"ms-w-managed"},"status":{"state":"running"}},
          {"id":"22222222-2222-2222-2222-222222222222","configuration":{"id":"ms-w-unmanaged","image":{"reference":"ubuntu:24.04"}},"status":"stopped"},
          {"id":"33333333-3333-3333-3333-333333333333","configuration":{"id":"ordinary"},"status":{"state":"paused"}}
        ]
        """#
        let cli = ExternalStubCLI(results: [.success(Data(json.utf8))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.set("w-managed", record("managed"))
        let before = FileManager.default.contents(atPath: fixture.storePath)
        let service = ExternalServices(docker: nil, apple: cli, records: fixture.store, ledger: CommandLedger())

        let result = await service.list()

        XCTAssertEqual(result.services.map(\.id), ["apple:22222222-2222-2222-2222-222222222222", "apple:33333333-3333-3333-3333-333333333333"])
        XCTAssertEqual(result.services[0].name, "ms-w-unmanaged", "a name prefix alone must not adopt or hide a container")
        XCTAssertEqual(result.services[0].image, "ubuntu:24.04")
        XCTAssertEqual(result.services[0].kind, .vm)
        XCTAssertEqual(result.services[0].state, .stopped)
        XCTAssertEqual(result.services[1].state, .unknown)
        XCTAssertEqual(cli.calls, [ExternalCall(arguments: ["list", "--all", "--format", "json"], timeout: 30)])
        XCTAssertEqual(FileManager.default.contents(atPath: fixture.storePath), before, "discovery must not write the managed records")
    }

    func testMissingRuntimesAreOmittedWithoutWarnings() async {
        let fixture = try! makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = ExternalServices(docker: nil, apple: nil, records: fixture.store, ledger: CommandLedger())

        let result = await service.list()

        XCTAssertEqual(result, ExternalServiceList(services: [], warnings: []))
    }

    func testRuntimeFailureProducesOneBoundedWarningAndNoMutation() async {
        let reason = String(repeating: "failure\n", count: 100)
        let cli = ExternalStubCLI(results: [.failure(EngineError.failed(reason))])
        let fixture = try! makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: CommandLedger())

        let result = await service.list()

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.warnings[0].runtime, .docker)
        XCTAssertLessThanOrEqual(result.warnings[0].message.utf8.count, 300)
        XCTAssertFalse(result.warnings[0].message.contains("\n"))
        XCTAssertEqual(cli.calls.map(\.arguments), [["ps", "--all", "--no-trunc", "--format", "{{json .}}"]])
    }

    func testUnknownIdIsNotFoundAndNeverRunsAnAction() async throws {
        let cli = ExternalStubCLI(results: [.success(Data("".utf8))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let ledger = CommandLedger()
        let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: ledger)

        do {
            _ = try await service.change(commandId: "cmd-unknown", id: "docker:missing", action: .start)
            XCTFail("an id absent from fresh discovery must be refused")
        } catch {
            XCTAssertEqual(error as? AgentError, .notFound)
        }
        XCTAssertNil(ledger.find("cmd-unknown"))
        XCTAssertEqual(cli.calls.map(\.arguments), [["ps", "--all", "--no-trunc", "--format", "{{json .}}"]])
    }

    func testDockerActionsUseExactArgvAndResolveFreshTargets() async throws {
        for (action, verb) in [(ExternalServiceAction.start, "start"), (.stop, "stop"), (.restart, "restart")] {
            let id = String(repeating: action == .start ? "a" : action == .stop ? "b" : "c", count: 64)
            let cli = ExternalStubCLI(results: [.success(dockerList(id: id)), .success(Data())])
            let fixture = try makeRecords()
            let ledger = CommandLedger()
            let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: ledger)
            let commandId = "cmd-\(verb)"

            let command = try await service.change(commandId: commandId, id: "docker:\(id)", action: action)
            let repeated = try await service.change(commandId: commandId, id: "docker:\(id)", action: action)

            XCTAssertEqual(command.state, .succeeded)
            XCTAssertEqual(command.type, action.commandType)
            XCTAssertNil(command.workloadId, "an external service is not a managed workload")
            XCTAssertEqual(repeated, command, "a repeated command id must not execute twice")
            XCTAssertEqual(ledger.find(commandId), command)
            XCTAssertEqual(cli.calls.map(\.arguments), [["ps", "--all", "--no-trunc", "--format", "{{json .}}"], [verb, id]])
            try? FileManager.default.removeItem(at: fixture.directory)
        }
    }

    func testAppleActionsUseNativeUuidAndRestartIsStopThenStart() async throws {
        for (action, verbs) in [(ExternalServiceAction.start, ["start"]), (.stop, ["stop"]), (.restart, ["stop", "start"])] {
            let uuid = "44444444-4444-4444-4444-444444444444"
            let cli = ExternalStubCLI(results: [.success(appleList(uuid: uuid))] + verbs.map { _ in Result<Data, Error>.success(Data()) })
            let fixture = try makeRecords()
            let service = ExternalServices(docker: nil, apple: cli, records: fixture.store, ledger: CommandLedger())

            let command = try await service.change(commandId: "cmd-apple-\(action.rawValue)", id: "apple:\(uuid)", action: action)

            XCTAssertEqual(command.state, .succeeded)
            XCTAssertEqual(cli.calls.map(\.arguments), [["list", "--all", "--format", "json"]] + verbs.map { [$0, uuid] })
            try? FileManager.default.removeItem(at: fixture.directory)
        }
    }

    func testManagedAppleIdCannotBeMutatedEvenWhenListed() async throws {
        let uuid = "55555555-5555-5555-5555-555555555555"
        let cli = ExternalStubCLI(results: [.success(appleList(uuid: uuid, name: "ms-w-managed"))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try fixture.store.set("w-managed", record("managed"))
        let service = ExternalServices(docker: nil, apple: cli, records: fixture.store, ledger: CommandLedger())

        do {
            _ = try await service.change(commandId: "cmd-managed", id: "apple:\(uuid)", action: .stop)
            XCTFail("a managed VM is not an external service")
        } catch {
            XCTAssertEqual(error as? AgentError, .notFound)
        }
        XCTAssertEqual(cli.calls.count, 1)
    }

    func testActionFailureIsPreservedInTheLedgerCommand() async throws {
        let id = String(repeating: "d", count: 64)
        let cli = ExternalStubCLI(results: [.success(dockerList(id: id)), .failure(EngineError.failed("docker says no\n" + String(repeating: "x", count: 400)))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let ledger = CommandLedger()
        let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: ledger)

        let command = try await service.change(commandId: "cmd-failed", id: "docker:\(id)", action: .stop)

        XCTAssertEqual(command.state, .failed)
        XCTAssertTrue(command.result?["error"]?.contains("docker says no") == true)
        XCTAssertLessThanOrEqual(command.result?["error"]?.utf8.count ?? 0, 300)
        XCTAssertEqual(ledger.find("cmd-failed"), command)
    }

    func testDiscoveryFailureDuringCommandBecomesFailedCommand() async throws {
        let cli = ExternalStubCLI(results: [.failure(EngineError.failed("daemon is unavailable"))])
        let fixture = try makeRecords()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let ledger = CommandLedger()
        let service = ExternalServices(docker: cli, apple: nil, records: fixture.store, ledger: ledger)

        let command = try await service.change(commandId: "cmd-unavailable", id: "docker:abcdef", action: .restart)

        XCTAssertEqual(command.state, .failed)
        XCTAssertEqual(command.result?["error"], "daemon is unavailable")
        XCTAssertEqual(cli.calls.count, 1, "an unavailable target must not receive a mutation")
    }

    private func makeRecords() throws -> (store: RecordStore, directory: URL, storePath: String) {
        let directory = FileManager.default.uniqueTemporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("workloads.json").path
        XCTAssertTrue(FileManager.default.createFile(atPath: path, contents: Data("{}".utf8)))
        return (RecordStore(path: path), directory, path)
    }

    private func record(_ name: String) -> WorkloadRecord {
        WorkloadRecord(name: name, kind: "vm", cpu: 1, ramMb: 512, diskGb: 1, gpuMode: "none", image: "ubuntu:24.04")
    }

    private func dockerList(id: String) -> Data {
        Data("{\"ID\":\"\(id)\",\"Names\":\"external\",\"State\":\"running\"}\n".utf8)
    }

    private func appleList(uuid: String, name: String = "external") -> Data {
        Data("{\"id\":\"\(uuid)\",\"configuration\":{\"id\":\"\(name)\"},\"status\":{\"state\":\"running\"}}".utf8)
    }
}

struct ExternalCall: Equatable {
    let arguments: [String]
    let timeout: TimeInterval
}

final class ExternalStubCLI: ContainerCLI, @unchecked Sendable {
    let path = "/test/runtime"
    private let lock = NSLock()
    private var results: [Result<Data, Error>]
    private var recorded: [ExternalCall] = []

    init(results: [Result<Data, Error>]) {
        self.results = results
    }

    var calls: [ExternalCall] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ arguments: [String], timeout: TimeInterval, input: Data?) async throws -> Data {
        XCTAssertNil(input)
        lock.lock()
        recorded.append(ExternalCall(arguments: arguments, timeout: timeout))
        let result = results.isEmpty ? .success(Data()) : results.removeFirst()
        lock.unlock()
        return try result.get()
    }
}
