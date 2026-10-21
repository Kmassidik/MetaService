import Foundation
import AgentCore

/// Workloads as Apple `container` microVMs. Each is a small Linux machine with systemd inside; kind is always "vm".
/// The tool has no setting for disk size, so `disk_gb` is a promise the budget keeps, not a limit the machine enforces.
actor AppleContainerEngine: Engine {
    nonisolated let capabilities = Capabilities(vm: true, container: false, gpuInVm: false, gpuInContainer: false)

    private let cli: ContainerCLI
    private let records: RecordStore
    private let backupDirectory: String
    private let defaultImage: String
    private let waitSeconds: Int
    private let starter: VmStarter
    private let reader: StoppedReasonReader
    private nonisolated let service = ServiceFlag()
    private var knownVersion: String?
    private var warnedStates: Set<String> = []
    /// VMs that are being made right now: they are "provisioning" until they have answered, even though the tool already lists them as running.
    private var starting: Set<String> = []
    /// Why each VM that stopped by itself stopped, looked up once per stop.
    private var reasons: [String: StoppedReason] = [:]
    private static let quick: TimeInterval = 30
    private static let slow: TimeInterval = 900

    init(cli: ContainerCLI, records: RecordStore, backupDirectory: String, defaultImage: String = AppleContainer.defaultImage, waitSeconds: Int = 90,
         readySeconds: Int = AppleContainer.readySeconds, settleSeconds: Int = AppleContainer.settleSeconds) {
        self.cli = cli
        self.records = records
        self.backupDirectory = backupDirectory
        self.defaultImage = defaultImage
        self.waitSeconds = waitSeconds
        starter = VmStarter(cli: cli, readySeconds: readySeconds, settleSeconds: settleSeconds)
        reader = StoppedReasonReader(cli: cli)
    }

    // MARK: reading

    static let engineName = "apple-container"

    /// The tool's version, asked once it answers and then remembered. Nil while it cannot be read: it is never guessed.
    func identity() async -> EngineIdentity {
        if knownVersion == nil {
            knownVersion = (try? await cli.run(AppleContainer.version, timeout: Self.quick)).flatMap { AppleContainer.parseVersion(String(decoding: $0, as: UTF8.self)) }
        }
        return EngineIdentity(name: Self.engineName, version: knownVersion)
    }

    /// What is wrong with reading right now. A stopped container service must not make the whole machine fall silent: it reports a problem and the machine keeps reporting in.
    nonisolated var problems: [HostProblem] {
        service.isDown ? [HostProblem(code: "container_service_stopped", message: "Apple's container service is not running on this Mac, so VMs cannot be listed or created right now.",
                                      fix: "Run `container system start` in a terminal on this Mac. MetaService starts it by itself the next time a VM is created.")] : []
    }

    func list() async throws -> [Workload] {
        let found = Dictionary(uniqueKeysWithValues: await liveContainers().map { ($0.name, $0) })
        var listed: [Workload] = []
        for (id, record) in records.all() {
            let live = found[AppleContainer.name(for: id)]
            let state = starting.contains(id) ? WorkloadState.provisioning : live.map { ContainerStates.workloadState($0.state) } ?? .failed
            listed.append(Workload(id: id, name: record.name, kind: WorkloadKind(rawValue: record.kind) ?? .vm, state: state,
                                   cpu: record.cpu, ramMb: record.ramMb, diskGb: record.diskGb, gpuMode: GpuMode(rawValue: record.gpuMode) ?? .none,
                                   address: live?.ipv4, bundleVersion: record.bundleVersion, stoppedReason: await stoppedReason(id, record, state, live: live),
                                   initMode: record.initMode.flatMap(InitMode.init(rawValue:))))
        }
        return listed
    }

    /// Why a VM that stopped by itself stopped. A VM the helper was told to stop, or one that is not stopped, has no reason.
    private func stoppedReason(_ id: String, _ record: WorkloadRecord, _ state: WorkloadState, live: ContainerInfo?) async -> StoppedReason? {
        guard live != nil, state == .stopped else {
            reasons[id] = nil
            return nil
        }
        if StoppedReasonPolicy.needsCapture(state: state, stopRequested: record.stopRequested, alreadyKnown: reasons[id] != nil) { reasons[id] = await reader.read(id) }
        return reasons[id]
    }

    /// The containers the tool shows, or none when it cannot answer (and the problem is remembered for `problems`).
    private func liveContainers() async -> [ContainerInfo] {
        do {
            let found = try await containers()
            service.isDown = false
            return found
        } catch {
            service.isDown = true
            return []
        }
    }

    private func containers() async throws -> [ContainerInfo] {
        let found = ContainerJson.parse(try await cli.run(AppleContainer.listAll, timeout: Self.quick))
        warnAboutUnmappedStates(found)
        return found
    }

    /// Says in the helper log, once per state word, when the tool prints a word the helper cannot map. Without it a changed tool shows only as a wrong state in the panel.
    private func warnAboutUnmappedStates(_ found: [ContainerInfo]) {
        for word in ContainerStates.unmappedWords(found) where warnedStates.insert(word).inserted {
            FileHandle.standardError.write(Data("metaservice-agent: \(ContainerStates.unmappedWarning(word))\n".utf8))
        }
    }

    private func find(_ id: String) async throws -> ContainerInfo? {
        try await containers().first { $0.name == AppleContainer.name(for: id) }
    }

    // MARK: lifecycle

    func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
        try await ensureSystemRunning()
        let image = request.image ?? defaultImage
        try await ensureImage(image)
        let record = WorkloadRecord(name: request.name, kind: request.kind.rawValue, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb,
                                    gpuMode: request.gpuMode.rawValue, image: image, stopRequested: false)
        try records.set(id, record)
        starting.insert(id)
        defer { starting.remove(id) }
        do {
            let started = try await starter.start(id: id, request: request, image: image)
            var known = record
            known.initMode = started.mode.rawValue
            try records.set(id, known)
            return Workload(id: id, name: request.name, kind: request.kind, state: .running, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb,
                            gpuMode: request.gpuMode, address: started.address, initMode: started.mode)
        } catch {
            _ = try? await cli.run(AppleContainer.delete(id), timeout: Self.quick)
            try? records.remove(id)
            throw error
        }
    }

    func setRunning(id: String, running: Bool) async throws {
        guard var record = records.all()[id] else { throw EngineError.notFound }
        record.stopRequested = !running
        try records.set(id, record)
        reasons[id] = nil
        _ = try await cli.run(running ? AppleContainer.start(id) : AppleContainer.stop(id), timeout: Self.slow)
        _ = try await waitUntil(id, running ? "running" : "stopped")
    }

    /// Exports the machine's whole filesystem to a tar file the Agent keeps. If there is no machine any more, there is nothing to keep.
    func backup(id: String) async throws -> String {
        guard records.all()[id] != nil else { throw EngineError.notFound }
        guard try await find(id) != nil else { return "none" }
        try FileManager.default.createDirectory(atPath: backupDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let file = "\(id)-\(stamp).tar"
        let path = backupDirectory + "/" + file
        _ = try await cli.run(AppleContainer.export(id, to: path), timeout: Self.slow)
        let size = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw EngineError.failed("the backup file is empty, so nothing was deleted") }
        return file
    }

    func delete(id: String) async throws {
        guard records.all()[id] != nil else { throw EngineError.notFound }
        if try await find(id) != nil { _ = try await cli.run(AppleContainer.delete(id), timeout: Self.quick) }
        guard try await find(id) == nil else { throw EngineError.failed("the machine is still there after delete") }
        reasons[id] = nil
        try records.remove(id)
    }

    func setBundleVersion(id: String, version: String?) async throws {
        guard var record = records.all()[id] else { throw EngineError.notFound }
        record.bundleVersion = version
        try records.set(id, record)
    }

    func push(id: String, hostPath: String, containerPath: String) async throws {
        guard records.all()[id] != nil else { throw EngineError.notFound }
        _ = try await cli.run(AppleContainer.copyIn(id, from: hostPath, to: containerPath), timeout: Self.quick)
    }

    func exec(id: String, arguments: [String], environment: [String: String]) async throws -> String {
        guard records.all()[id] != nil else { throw EngineError.notFound }
        return String(decoding: try await cli.run(AppleContainer.exec(id, arguments: arguments, environment: environment), timeout: Self.slow), as: UTF8.self)
    }

    func attach(id: String) async throws -> [String] {
        guard records.all()[id] != nil else { throw EngineError.notFound }
        return [cli.path] + (try AppleContainer.attach(id))
    }

    // MARK: helpers

    private func ensureSystemRunning() async throws {
        if await systemRunning() { return }
        _ = try? await cli.run(AppleContainer.systemStart, timeout: 120)
        guard await systemRunning() else { throw EngineError.failed("the container system is not running; start it once with `container system start`") }
    }

    private func systemRunning() async -> Bool {
        guard let output = try? await cli.run(AppleContainer.systemStatus, timeout: Self.quick) else { return false }
        return String(decoding: output, as: UTF8.self).split(separator: "\n").contains { $0.hasPrefix("status") && $0.contains("running") }
    }

    private func ensureImage(_ image: String) async throws {
        if (try? await cli.run(AppleContainer.imageInspect(image), timeout: Self.quick)) != nil { return }
        _ = try await cli.run(AppleContainer.imagePull(image), timeout: Self.slow)
    }

    private func waitUntil(_ id: String, _ state: String) async throws -> ContainerInfo {
        for _ in 0..<max(1, waitSeconds) {
            if let found = try await find(id), found.state == state, state != "running" || found.ipv4 != nil { return found }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw EngineError.failed("the machine did not reach \(state) in time")
    }
}

/// Whether the container service answered the last time it was asked. Read from outside the actor, so it is guarded by a lock.
private final class ServiceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var down = false

    var isDown: Bool {
        get { lock.withLock { down } }
        set { lock.withLock { down = newValue } }
    }
}
