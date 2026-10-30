import Foundation

/// The size words of create_vm: the same three presets as the panel's Create VM window (frontend/src/lib/vmSize.ts), and Custom.
public enum McpSize: String, CaseIterable, Equatable {
    case small, medium, large, custom

    public struct Dimensions: Equatable {
        public let vcpu: Int
        public let ramMb: Int
        public let diskGb: Int

        public init(vcpu: Int, ramMb: Int, diskGb: Int) {
            self.vcpu = vcpu
            self.ramMb = ramMb
            self.diskGb = diskGb
        }
    }

    /// Nil for custom: the caller names the numbers.
    public var preset: Dimensions? {
        switch self {
        case .small: return Dimensions(vcpu: 1, ramMb: 2048, diskGb: 20)
        case .medium: return Dimensions(vcpu: 2, ramMb: 4096, diskGb: 40)
        case .large: return Dimensions(vcpu: 4, ramMb: 8192, diskGb: 60)
        case .custom: return nil
        }
    }

    /// The presets, smallest first.
    public static var presets: [(size: McpSize, dimensions: Dimensions)] {
        [small, medium, large].compactMap { size in size.preset.map { (size, $0) } }
    }

    /// True when any number is above the medium preset's: that is where a person has to approve.
    public static func exceedsMedium(_ size: Dimensions) -> Bool {
        guard let medium = McpSize.medium.preset else { return false }
        return size.vcpu > medium.vcpu || size.ramMb > medium.ramMb || size.diskGb > medium.diskGb
    }

    public static let customVcpu = 1...64
    public static let customRamMb = 512...1_048_576
    public static let customDiskGb = 1...100_000
}
