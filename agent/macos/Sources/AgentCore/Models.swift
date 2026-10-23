import Foundation

public enum WorkloadKind: String, Codable, CaseIterable { case vm, container }
public enum WorkloadState: String, Codable { case provisioning, running, stopped, failed, deleting }
public enum GpuMode: String, Codable { case none, container, passthrough }

public struct Gpu: Codable, Equatable {
    public let vendor: String
    public let model: String
    public let memoryMb: Int?

    public init(vendor: String, model: String, memoryMb: Int?) {
        self.vendor = vendor
        self.model = model
        self.memoryMb = memoryMb
    }
}

public struct Capabilities: Codable, Equatable {
    public let vm: Bool
    public let container: Bool
    public let gpuInVm: Bool
    public let gpuInContainer: Bool

    public init(vm: Bool, container: Bool, gpuInVm: Bool, gpuInContainer: Bool) {
        self.vm = vm
        self.container = container
        self.gpuInVm = gpuInVm
        self.gpuInContainer = gpuInContainer
    }
}

/// What the machine is, measured. `free` numbers are added by the budget, not read from the system.
public struct MachineSpecs: Equatable {
    public let os: String
    public let arch: String
    public let cpuCores: Int
    public let ramTotalMb: Int
    public let diskTotalGb: Int
    public let gpu: [Gpu]

    public init(os: String, arch: String, cpuCores: Int, ramTotalMb: Int, diskTotalGb: Int, gpu: [Gpu]) {
        self.os = os
        self.arch = arch
        self.cpuCores = cpuCores
        self.ramTotalMb = ramTotalMb
        self.diskTotalGb = diskTotalGb
        self.gpu = gpu
    }

    /// The same machine with fresh RAM and disk totals.
    public func withTotals(ramTotalMb: Int, diskTotalGb: Int) -> MachineSpecs {
        MachineSpecs(os: os, arch: arch, cpuCores: cpuCores, ramTotalMb: ramTotalMb, diskTotalGb: diskTotalGb, gpu: gpu)
    }
}

/// The facts the Root receives: the specs plus how much room is left for workloads.
/// Something on this machine that stops it from running workloads, with the way to fix it. Reported in the facts; the Root places nothing here until it is gone.
public struct HostProblem: Encodable, Equatable {
    public let code: String
    public let message: String
    public let fix: String

    public init(code: String, message: String, fix: String) {
        self.code = code
        self.message = message
        self.fix = fix
    }
}

/// The engine as the facts report it: its name, its version when it can tell (null otherwise), and whether it works right now.
public struct EngineInfo: Encodable, Equatable {
    public let name: String
    public let version: String?
    public let ready: Bool

    public init(identity: EngineIdentity, ready: Bool) {
        name = identity.name
        version = identity.version
        self.ready = ready
    }

    enum CodingKeys: String, CodingKey { case name, version, ready }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(name, forKey: .name)
        try box.encode(version, forKey: .version)
        try box.encode(ready, forKey: .ready)
    }
}

public struct Facts: Encodable, Equatable {
    public let specs: MachineSpecs
    public let freeRamMb: Int
    public let freeDiskGb: Int
    public let capabilities: Capabilities
    public let problems: [HostProblem]
    public let agentVersion: String
    public let engine: EngineInfo
    /// The SHA-256 of this program's file (see AgentBuild). Left out of the facts when it is not known.
    public let agentBuild: String?

    enum CodingKeys: String, CodingKey {
        case os, arch, cpuCores, ramTotalMb, diskTotalGb, freeRamMb, freeDiskGb, gpu, capabilities, problems, agentVersion, engine, agentBuild
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(specs.os, forKey: .os)
        try box.encode(specs.arch, forKey: .arch)
        try box.encode(specs.cpuCores, forKey: .cpuCores)
        try box.encode(specs.ramTotalMb, forKey: .ramTotalMb)
        try box.encode(specs.diskTotalGb, forKey: .diskTotalGb)
        try box.encode(freeRamMb, forKey: .freeRamMb)
        try box.encode(freeDiskGb, forKey: .freeDiskGb)
        try box.encode(specs.gpu, forKey: .gpu)
        try box.encode(capabilities, forKey: .capabilities)
        try box.encode(problems, forKey: .problems)
        try box.encode(agentVersion, forKey: .agentVersion)
        try box.encode(engine, forKey: .engine)
        try box.encodeIfPresent(agentBuild, forKey: .agentBuild)
    }

    public init(specs: MachineSpecs, freeRamMb: Int, freeDiskGb: Int, capabilities: Capabilities, problems: [HostProblem] = [], agentVersion: String, engine: EngineInfo, agentBuild: String? = nil) {
        self.agentBuild = agentBuild
        self.agentVersion = agentVersion
        self.engine = engine
        self.problems = problems
        self.specs = specs
        self.freeRamMb = freeRamMb
        self.freeDiskGb = freeDiskGb
        self.capabilities = capabilities
    }
}

public struct Workload: Encodable, Equatable {
    public let id: String
    public let name: String
    public let kind: WorkloadKind
    public var state: WorkloadState
    public let cpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMode: GpuMode
    public var address: String?
    public var bundleVersion: String?
    /// Only while the VM is stopped and stopped by itself. Left out of the JSON otherwise.
    public var stoppedReason: StoppedReason?
    /// How the VM came up, when the helper knows. Left out of the JSON otherwise.
    public var initMode: InitMode?

    public init(id: String, name: String, kind: WorkloadKind, state: WorkloadState, cpu: Int, ramMb: Int, diskGb: Int, gpuMode: GpuMode, address: String? = nil, bundleVersion: String? = nil,
                stoppedReason: StoppedReason? = nil, initMode: InitMode? = nil) {
        self.stoppedReason = stoppedReason
        self.initMode = initMode
        self.id = id
        self.name = name
        self.kind = kind
        self.state = state
        self.cpu = cpu
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.gpuMode = gpuMode
        self.address = address
        self.bundleVersion = bundleVersion
    }

    enum CodingKeys: String, CodingKey { case id, name, kind, state, cpu, ramMb, diskGb, gpuMode, address, bundleVersion, stoppedReason, initMode }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(kind, forKey: .kind)
        try box.encode(state, forKey: .state)
        try box.encode(cpu, forKey: .cpu)
        try box.encode(ramMb, forKey: .ramMb)
        try box.encode(diskGb, forKey: .diskGb)
        try box.encode(gpuMode, forKey: .gpuMode)
        try box.encode(address, forKey: .address)
        try box.encode(bundleVersion, forKey: .bundleVersion)
        try box.encodeIfPresent(stoppedReason, forKey: .stoppedReason)
        try box.encodeIfPresent(initMode, forKey: .initMode)
    }
}

public enum CommandType: String, Codable { case create, start, stop, delete, bundleInstall = "bundle_install", bundleUninstall = "bundle_uninstall" }
public enum CommandState: String, Codable { case queued, running, succeeded, failed }

public struct Command: Codable, Equatable {
    public let commandId: String
    public let type: CommandType
    public var state: CommandState
    public var workloadId: String?
    public var result: [String: String]?

    public init(commandId: String, type: CommandType, state: CommandState, workloadId: String? = nil, result: [String: String]? = nil) {
        self.commandId = commandId
        self.type = type
        self.state = state
        self.workloadId = workloadId
        self.result = result
    }

    enum CodingKeys: String, CodingKey { case commandId, type, state, workloadId, result }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(commandId, forKey: .commandId)
        try box.encode(type, forKey: .type)
        try box.encode(state, forKey: .state)
        try box.encodeIfPresent(workloadId, forKey: .workloadId)
        try box.encode(result, forKey: .result)
    }
}
