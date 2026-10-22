import Foundation

/// One graphics chip as the system's registry shows it, before the limits are applied. Everything but the name and vendor is nil when the registry does not say.
public struct GpuReading: Equatable {
    public let name: String
    public let vendor: String
    public let utilizationPercent: Double?
    public let memoryUsedBytes: UInt64?
    /// True when the chip uses the computer's own memory (Apple Silicon): the answer then reports the machine's memory as the total.
    public let sharesSystemMemory: Bool

    public init(name: String, vendor: String, utilizationPercent: Double?, memoryUsedBytes: UInt64?, sharesSystemMemory: Bool) {
        self.name = name; self.vendor = vendor; self.utilizationPercent = utilizationPercent
        self.memoryUsedBytes = memoryUsedBytes; self.sharesSystemMemory = sharesSystemMemory
    }
}

/// Reads the properties of one `IOAccelerator` registry entry (the numbers `ioreg` shows; no root). Pure: the system call lives in the Agent target.
public enum AppleGpuRegistry {
    public static let vendorApple = "apple"
    public static let vendorUnknown = "unknown"
    static let statisticsKey = "PerformanceStatistics"
    static let utilizationKey = "Device Utilization %"
    static let memoryInUseKey = "In use system memory"
    static let modelKey = "model"
    static let classKey = "IOClass"
    static let appleClassPrefix = "AGX"
    static let nameSuffix = "GPU"
    static let genericName = "Apple GPU"

    /// nil when the entry carries no statistics at all (then it is not a chip worth showing).
    /// `brand` is the computer's chip name (for example "Apple M3 Max"), used when the entry has no `model`.
    public static func reading(from properties: [String: Any], brand: String?) -> GpuReading? {
        guard let statistics = properties[statisticsKey] as? [String: Any] else { return nil }
        let utilization = number(statistics[utilizationKey]).flatMap { (0...100).contains($0) ? $0 : nil }
        let memoryInUse = number(statistics[memoryInUseKey]).flatMap { $0 >= 0 && $0 < Double(UInt64.max) ? UInt64($0) : nil }
        guard utilization != nil || memoryInUse != nil else { return nil }
        let isApple = (properties[classKey] as? String)?.hasPrefix(appleClassPrefix) == true
        let chip = text(properties[modelKey]) ?? (isApple ? brand : nil)
        return GpuReading(name: name(chip), vendor: isApple ? vendorApple : vendorUnknown, utilizationPercent: utilization, memoryUsedBytes: memoryInUse, sharesSystemMemory: isApple)
    }

    /// "Apple M3 Max" becomes "Apple M3 Max GPU"; a name that already says GPU stays as it is.
    static func name(_ chip: String?) -> String {
        guard let chip, !chip.isEmpty else { return genericName }
        return chip.localizedCaseInsensitiveContains(nameSuffix) ? chip : "\(chip) \(nameSuffix)"
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    /// The registry gives text as a string or as bytes ending in zeros.
    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        guard let data = value as? Data, let string = String(data: data, encoding: .utf8) else { return nil }
        return string.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines)).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
