import Foundation
import RootCore

/// JSON shapes for operators. Missing values are sent as null, so the shape never changes.
public struct WorkloadSummary: Encodable, Equatable {
    public let id: String
    public let name: String
    public let kind: String
    public let state: String
    public let cpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMode: String
    public let address: String?
    public let bundleVersion: String?
    /// Why the VM stopped, when it stopped by itself and the helper said why. Null otherwise.
    public let stoppedReason: StoppedReasonReport?
    /// "systemd" or "plain" (no systemd); null when the helper does not say.
    public let initMode: String?
    /// The app (OpenClaw, Hermes) wanted inside this VM and how setting it up stands. Null when none is wanted.
    public var app: WorkloadAppSummary? = nil
    /// The GPU memory this container may use, in GB; null when it shares the whole card.
    public var gpuMemoryGb: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, kind, state, cpu, ramMb, diskGb, gpuMode, address, bundleVersion, stoppedReason, initMode, app, gpuMemoryGb
    }

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
        try box.encode(stoppedReason, forKey: .stoppedReason)
        try box.encode(initMode, forKey: .initMode)
        try box.encode(app, forKey: .app)
        try box.encode(gpuMemoryGb, forKey: .gpuMemoryGb)
    }
}

/// What the machine list says about a VM's app: the name, how it stands (`none`, `installing`, `ready`, `failed`) and the plain message of a failure.
public struct WorkloadAppSummary: Encodable, Equatable {
    public let name: String
    public let state: String
    public let message: String?

    init(_ record: AppRecord) {
        name = record.app
        state = record.phase.rawValue
        message = record.message
    }

    enum CodingKeys: String, CodingKey { case name, state, message }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(name, forKey: .name)
        try box.encode(state, forKey: .state)
        try box.encode(message, forKey: .message)
    }
}

public struct MachineSummary: Encodable, Equatable {
    public let id: String
    public let name: String
    public let ip: String?
    public let os: String?
    public let arch: String?
    public let cpuCores: Int?
    /// The CPU's name as the helper reported it (cleaned by the parent); null for a helper that does not say.
    public let cpuModel: String?
    public let ramTotalMb: Int?
    public let diskTotalGb: Int?
    public let freeRamMb: Int?
    public let freeDiskGb: Int?
    public let gpu: [GpuInfo]
    public let capabilities: Capabilities?
    public let settings: MachineSettings?
    public let problems: [HostProblem]
    public let agentVersion: String?
    /// The SHA-256 of the helper's program file as the helper reported it; null for a helper that does not say.
    public let agentBuild: String?
    public let engine: EngineReport?
    /// What the helper can offer for sandboxes; null when it does not say, or says it cannot run any.
    public let sandbox: SandboxFacts?
    public let bundleVersion: String?
    public let state: String
    public let lastSeen: String?
    public let workloads: [WorkloadSummary]
    /// How much of the card's memory is promised to containers; null when the machine has no NVIDIA card that can be shared or does not say its memory.
    public let gpuBooking: GpuBookingSummary?

    enum CodingKeys: String, CodingKey {
        case id, name, ip, os, arch, cpuCores, ramTotalMb, diskTotalGb, freeRamMb, freeDiskGb, cpuModel
        case gpu, capabilities, settings, problems, agentVersion, agentBuild, engine, sandbox, bundleVersion, state, lastSeen, workloads, gpuBooking
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(ip, forKey: .ip)
        try box.encode(os, forKey: .os)
        try box.encode(arch, forKey: .arch)
        try box.encode(cpuCores, forKey: .cpuCores)
        try box.encode(cpuModel, forKey: .cpuModel)
        try box.encode(ramTotalMb, forKey: .ramTotalMb)
        try box.encode(diskTotalGb, forKey: .diskTotalGb)
        try box.encode(freeRamMb, forKey: .freeRamMb)
        try box.encode(freeDiskGb, forKey: .freeDiskGb)
        try box.encode(gpu, forKey: .gpu)
        try box.encode(capabilities, forKey: .capabilities)
        try box.encode(settings, forKey: .settings)
        try box.encode(problems, forKey: .problems)
        try box.encode(agentVersion, forKey: .agentVersion)
        try box.encode(agentBuild, forKey: .agentBuild)
        try box.encode(engine, forKey: .engine)
        try box.encode(sandbox, forKey: .sandbox)
        try box.encode(bundleVersion, forKey: .bundleVersion)
        try box.encode(state, forKey: .state)
        try box.encode(lastSeen, forKey: .lastSeen)
        try box.encode(workloads, forKey: .workloads)
        try box.encode(gpuBooking, forKey: .gpuBooking)
    }
}
