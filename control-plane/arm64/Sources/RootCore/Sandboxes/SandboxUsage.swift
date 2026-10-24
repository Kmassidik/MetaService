import Foundation

/// What one finished run counts: its seconds, and those seconds times the vCPU and the memory it held.
public struct SandboxUsageTotals: Encodable, Equatable {
    public let seconds: Int
    public let vcpuSeconds: Int
    public let ramMbSeconds: Int

    public init(seconds: Int, vcpuSeconds: Int, ramMbSeconds: Int) {
        self.seconds = seconds
        self.vcpuSeconds = vcpuSeconds
        self.ramMbSeconds = ramMbSeconds
    }
}

/// The usage arithmetic, pure: a start, an end and a shape in, the row to add up out. Whole seconds, rounded down, and
/// never negative, because a helper clock can be a moment ahead of the parent's.
public enum SandboxUsageMath {
    public static func seconds(from start: Date, to end: Date) -> Int {
        Int(max(0, end.timeIntervalSince(start)).rounded(.down))
    }

    public static func totals(from start: Date, to end: Date, shape: SandboxShape) -> SandboxUsageTotals {
        let seconds = seconds(from: start, to: end)
        return SandboxUsageTotals(seconds: seconds, vcpuSeconds: seconds * shape.vcpu, ramMbSeconds: seconds * shape.ramMb)
    }
}
