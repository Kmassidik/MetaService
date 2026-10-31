import Foundation

/// The limits of one token. Defaults live here, in code; the panel may change them when a token is made.
public struct McpQuotas: Equatable {
    public static let defaultMaxVms = 3
    public static let defaultMaxVcpu = 8
    public static let defaultMaxRamMb = 16_384
    public static let defaultMaxDiskGb = 200
    public static let defaultCreatesPerDay = 10
    public static let defaultGpuMemoryGb = 8

    static let ranges: [(key: String, range: ClosedRange<Int>)] = [
        ("max_vms", 1...100), ("max_vcpu", 1...256), ("max_ram_mb", 512...4_194_304), ("max_disk_gb", 1...100_000),
        ("creates_per_day", 1...1000), ("gpu_memory_gb", 1...1024),
    ]
    static let keys = Set(ranges.map(\.key))

    public let maxVms: Int
    public let maxVcpu: Int
    public let maxRamMb: Int
    public let maxDiskGb: Int
    public let createsPerDay: Int
    /// The most GPU memory one VM may ask for. Only used when the token has the `gpu` scope.
    public let gpuMemoryGb: Int

    public static let defaults = McpQuotas(maxVms: defaultMaxVms, maxVcpu: defaultMaxVcpu, maxRamMb: defaultMaxRamMb, maxDiskGb: defaultMaxDiskGb,
                                           createsPerDay: defaultCreatesPerDay, gpuMemoryGb: defaultGpuMemoryGb)

    public init(maxVms: Int, maxVcpu: Int, maxRamMb: Int, maxDiskGb: Int, createsPerDay: Int, gpuMemoryGb: Int) {
        self.maxVms = maxVms
        self.maxVcpu = maxVcpu
        self.maxRamMb = maxRamMb
        self.maxDiskGb = maxDiskGb
        self.createsPerDay = createsPerDay
        self.gpuMemoryGb = gpuMemoryGb
    }

    /// The quotas a panel body names; every field it leaves out keeps its default. Unknown fields and numbers out of range are refused.
    public init(object: StrictObject) throws {
        func value(_ key: String, _ fallback: Int) throws -> Int {
            guard let range = Self.ranges.first(where: { $0.key == key })?.range else { return fallback }
            return object.has(key) ? try object.int(key, range: range) : fallback
        }
        maxVms = try value("max_vms", Self.defaultMaxVms)
        maxVcpu = try value("max_vcpu", Self.defaultMaxVcpu)
        maxRamMb = try value("max_ram_mb", Self.defaultMaxRamMb)
        maxDiskGb = try value("max_disk_gb", Self.defaultMaxDiskGb)
        createsPerDay = try value("creates_per_day", Self.defaultCreatesPerDay)
        gpuMemoryGb = try value("gpu_memory_gb", Self.defaultGpuMemoryGb)
    }

    /// As stored and as shown to the panel.
    public var json: [String: Int] {
        ["max_vms": maxVms, "max_vcpu": maxVcpu, "max_ram_mb": maxRamMb, "max_disk_gb": maxDiskGb, "creates_per_day": createsPerDay, "gpu_memory_gb": gpuMemoryGb]
    }

    /// Reads what `json` wrote. A missing or damaged field falls back to its default, so an old row never locks a token out.
    public init(stored text: String) {
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        func value(_ key: String, _ fallback: Int) -> Int { (object[key] as? Int) ?? fallback }
        self.init(maxVms: value("max_vms", Self.defaultMaxVms), maxVcpu: value("max_vcpu", Self.defaultMaxVcpu), maxRamMb: value("max_ram_mb", Self.defaultMaxRamMb),
                  maxDiskGb: value("max_disk_gb", Self.defaultMaxDiskGb), createsPerDay: value("creates_per_day", Self.defaultCreatesPerDay),
                  gpuMemoryGb: value("gpu_memory_gb", Self.defaultGpuMemoryGb))
    }
}

/// What a token already uses: its alive VMs and the creates it made in the last 24 hours.
public struct McpUsage: Equatable {
    public let aliveVms: Int
    public let vcpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let createsLastDay: Int

    public init(aliveVms: Int, vcpu: Int, ramMb: Int, diskGb: Int, createsLastDay: Int) {
        self.aliveVms = aliveVms
        self.vcpu = vcpu
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.createsLastDay = createsLastDay
    }
}

/// The size of the VM a token asks for.
public struct McpWish: Equatable {
    public let vcpu: Int
    public let ramMb: Int
    public let diskGb: Int
    public let gpuMemoryGb: Int?

    public init(vcpu: Int, ramMb: Int, diskGb: Int, gpuMemoryGb: Int?) {
        self.vcpu = vcpu
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.gpuMemoryGb = gpuMemoryGb
    }
}

/// Says no, in a sentence that names the limit, what is used and what is left, and what to do next. Nil when the wish fits every limit.
public enum McpQuotaCheck {
    public static func refusal(_ quotas: McpQuotas, used: McpUsage, wish: McpWish) -> String? {
        if used.aliveVms >= quotas.maxVms {
            return "max_vms is \(quotas.maxVms) and \(used.aliveVms) \(used.aliveVms == 1 ? "is" : "are") alive: delete one first."
        }
        if used.createsLastDay >= quotas.createsPerDay {
            return "creates_per_day is \(quotas.createsPerDay) and \(used.createsLastDay) were made in the last 24 hours: try again later."
        }
        if let gpu = wish.gpuMemoryGb, gpu > quotas.gpuMemoryGb {
            return "gpu_memory_gb is capped at \(quotas.gpuMemoryGb) for this person and \(gpu) was asked for: ask for \(quotas.gpuMemoryGb) or less."
        }
        let sums: [(name: String, limit: Int, used: Int, needed: Int)] = [
            ("max_vcpu", quotas.maxVcpu, used.vcpu, wish.vcpu),
            ("max_ram_mb", quotas.maxRamMb, used.ramMb, wish.ramMb),
            ("max_disk_gb", quotas.maxDiskGb, used.diskGb, wish.diskGb),
        ]
        return sums.first { $0.used + $0.needed > $0.limit }.map(sumRefusal)
    }

    private static func sumRefusal(_ sum: (name: String, limit: Int, used: Int, needed: Int)) -> String {
        let left = max(0, sum.limit - sum.used)
        return "\(sum.name) is \(sum.limit) and \(sum.used) are in use: this VM needs \(sum.needed) and only \(left) is left. Ask for a smaller size or delete a VM first."
    }
}
