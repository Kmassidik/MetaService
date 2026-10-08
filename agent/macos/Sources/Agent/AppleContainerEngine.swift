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
    private static let quick: TimeInterval = 30
    private static let slow: TimeInterval = 900

    init(cli: ContainerCLI, records: RecordStore, backupDirectory: String, defaultImage: String = AppleContainer.defaultImage, waitSeconds: Int = 90) {
        self.cli = cli
        self.records = records
        self.backupDirectory = backupDirectory
        self.defaultImage = defaultImage
        self.waitSeconds = waitSeconds
    }

    // MARK: reading

    func list() async throws -> [Workload] {
        let found = Dictionary(uniqueKeysWithValues: try await containers().map { ($0.name, $0) })
        return records.all().map { id, record in
            let live = found[AppleContainer.name(for: id)]
            return Workload(id: id, name: record.name, kind: WorkloadKind(rawValue: record.kind) ?? .vm, state: live.map { ContainerStates.workloadState($0.state) } ?? .failed,
                            cpu: record.cpu, ramMb: record.ramMb, diskGb: record.diskGb, gpuMode: GpuMode(rawValue: record.gpuMode) ?? .none,
                            address: live?.ipv4, bundleVersion: record.bundleVersion)
        }
    }

    private func containers() async throws -> [ContainerInfo] {
        ContainerJson.parse(try await cli.run(AppleContainer.listAll, timeout: Self.quick))
    }

    private func find(_ id: String) async throws -> ContainerInfo? {
        try await containers().first { $0.name == AppleContainer.name(for: id) }
    }

    // MARK: lifecycle

    func create(id: String, request: CreateWorkloadRequest) async throws -> Workload {
        try await ensureSystemRunning()
        let image = request.image ?? defaultImage
        try await ensureImage(image)
        try records.set(id, WorkloadRecord(name: request.name, kind: request.kind.rawValue, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb,
                                           gpuMode: request.gpuMode.rawValue, image: image))
        do {
            _ = try await cli.run(AppleContainer.run(id: id, request: request, image: image), timeout: Self.slow)
            let info = try await waitUntil(id, "running")
            return Workload(id: id, name: request.name, kind: request.kind, state: .running, cpu: request.cpu, ramMb: request.ramMb, diskGb: request.diskGb,
                            gpuMode: request.gpuMode, address: info.ipv4)
        } catch {
            _ = try? await cli.run(AppleContainer.delete(id), timeout: Self.quick)
            try? records.remove(id)
            throw error
        }
    }

    func setRunning(id: String, running: Bool) async throws {
        guard records.all()[id] != nil else { throw EngineError.notFound }
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
        try records.remove(id)
    }

    func setBundleVersion(id: String, version: String) async throws {
        guard var record = records.all()[id] else { throw EngineError.notFound }
        record.bundleVersion = version
        try records.set(id, record)
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
