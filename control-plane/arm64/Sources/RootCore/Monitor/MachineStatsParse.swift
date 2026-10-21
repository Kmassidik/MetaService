import Foundation

public enum StatsError: Error, Equatable {
    case tooBig
    case notAnAnswer
}

extension MachineStats {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Reads a helper's answer and holds it to the contract's limits. An answer that is too big or does not have the right shape is refused.
    public static func parse(_ data: Data) throws -> MachineStats {
        guard data.count <= maxAnswerBytes else { throw StatsError.tooBig }
        guard let raw = try? decoder.decode(MachineStats.self, from: data) else { throw StatsError.notAnAnswer }
        return raw.limited()
    }

    func limited() -> MachineStats {
        var kept = self
        kept.takenAt = Self.cut(takenAt, Self.maxTimeCharacters)
        kept.uptimeSeconds = max(uptimeSeconds, 0)
        kept.cpu = cpu.limited()
        kept.memory = memory.limited()
        kept.disks = disks.prefix(Self.maxDisks).map { $0.limited() }
        kept.network = network.limited()
        kept.gpus = Self.limitedGpus(gpus)
        kept.processes = processes.prefix(Self.maxProcesses).map { $0.limited() }
        return kept
    }

    private static func limitedGpus(_ gpus: [Gpu]?) -> [Gpu]? {
        guard let gpus, !gpus.isEmpty else { return nil }
        return gpus.prefix(maxGpus).map { $0.limited() }
    }

    static func cut(_ text: String, _ characters: Int) -> String { String(text.prefix(characters)) }
    static func percent(_ value: Double?) -> Double? { value.map { $0.isFinite ? min(max($0, 0), 100) : 0 } }
    static func rate(_ value: Double?) -> Double? { value.map { $0.isFinite ? max($0, 0) : 0 } }
    static func bytes(_ value: Int) -> Int { max(value, 0) }
}

extension MachineStats.Cpu {
    fileprivate func limited() -> MachineStats.Cpu {
        let cores = coresPercent?.prefix(MachineStats.maxCores).map { MachineStats.percent($0) ?? 0 }
        return .init(coreCount: min(max(coreCount, 1), MachineStats.maxCores), totalPercent: MachineStats.percent(totalPercent), coresPercent: cores,
                     load: .init(one: MachineStats.rate(load.one), five: MachineStats.rate(load.five), fifteen: MachineStats.rate(load.fifteen)))
    }
}

extension MachineStats.Memory {
    fileprivate func limited() -> MachineStats.Memory {
        .init(totalBytes: MachineStats.bytes(totalBytes), usedBytes: MachineStats.bytes(usedBytes), cachedBytes: MachineStats.bytes(cachedBytes), freeBytes: MachineStats.bytes(freeBytes),
              swapTotalBytes: MachineStats.bytes(swapTotalBytes), swapUsedBytes: MachineStats.bytes(swapUsedBytes))
    }
}

extension MachineStats.Disk {
    fileprivate func limited() -> MachineStats.Disk {
        .init(mount: MachineStats.cut(mount, MachineStats.maxMountCharacters), name: MachineStats.cut(name, MachineStats.maxTextCharacters), fs: MachineStats.cut(fs, MachineStats.maxFsCharacters),
              totalBytes: MachineStats.bytes(totalBytes), usedBytes: MachineStats.bytes(usedBytes), freeBytes: MachineStats.bytes(freeBytes))
    }
}

extension MachineStats.Network {
    fileprivate func limited() -> MachineStats.Network {
        .init(receivedTotalBytes: MachineStats.bytes(receivedTotalBytes), sentTotalBytes: MachineStats.bytes(sentTotalBytes),
              receivedBytesPerSecond: MachineStats.rate(receivedBytesPerSecond), sentBytesPerSecond: MachineStats.rate(sentBytesPerSecond))
    }
}

extension MachineStats.Gpu {
    fileprivate func limited() -> MachineStats.Gpu {
        .init(name: MachineStats.cut(name, MachineStats.maxTextCharacters), utilizationPercent: MachineStats.percent(utilizationPercent),
              memoryUsedBytes: memoryUsedBytes.map(MachineStats.bytes), memoryTotalBytes: memoryTotalBytes.map(MachineStats.bytes), temperatureCelsius: temperatureCelsius)
    }
}

extension MachineStats.Process {
    fileprivate func limited() -> MachineStats.Process {
        .init(pid: max(pid, 0), name: MachineStats.cut(name, MachineStats.maxTextCharacters), user: MachineStats.cut(user, MachineStats.maxTextCharacters),
              cpuPercent: MachineStats.rate(cpuPercent), memoryBytes: MachineStats.bytes(memoryBytes))
    }
}
