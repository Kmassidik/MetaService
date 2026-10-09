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

    enum CodingKeys: String, CodingKey {
        case id, name, kind, state, cpu, ramMb, diskGb, gpuMode, address, bundleVersion
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
    }
}

public struct MachineSummary: Encodable, Equatable {
    public let id: String
    public let name: String
    public let ip: String?
    public let os: String?
    public let arch: String?
    public let cpuCores: Int?
    public let ramTotalMb: Int?
    public let diskTotalGb: Int?
    public let freeRamMb: Int?
    public let freeDiskGb: Int?
    public let gpu: [GpuInfo]
    public let capabilities: Capabilities?
    public let problems: [HostProblem]
    public let agentVersion: String?
    public let bundleVersion: String?
    public let state: String
    public let lastSeen: String?
    public let workloads: [WorkloadSummary]

    enum CodingKeys: String, CodingKey {
        case id, name, ip, os, arch, cpuCores, ramTotalMb, diskTotalGb, freeRamMb, freeDiskGb
        case gpu, capabilities, problems, agentVersion, bundleVersion, state, lastSeen, workloads
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(id, forKey: .id)
        try box.encode(name, forKey: .name)
        try box.encode(ip, forKey: .ip)
        try box.encode(os, forKey: .os)
        try box.encode(arch, forKey: .arch)
        try box.encode(cpuCores, forKey: .cpuCores)
        try box.encode(ramTotalMb, forKey: .ramTotalMb)
        try box.encode(diskTotalGb, forKey: .diskTotalGb)
        try box.encode(freeRamMb, forKey: .freeRamMb)
        try box.encode(freeDiskGb, forKey: .freeDiskGb)
        try box.encode(gpu, forKey: .gpu)
        try box.encode(capabilities, forKey: .capabilities)
        try box.encode(problems, forKey: .problems)
        try box.encode(agentVersion, forKey: .agentVersion)
        try box.encode(bundleVersion, forKey: .bundleVersion)
        try box.encode(state, forKey: .state)
        try box.encode(lastSeen, forKey: .lastSeen)
        try box.encode(workloads, forKey: .workloads)
    }
}
