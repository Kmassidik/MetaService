import Foundation

/// One fresh look at the machine. RAM in MB, disk in GB.
public struct MachineReading: Equatable, Sendable {
    public let ramTotalMb: Int
    public let diskTotalGb: Int
    public let diskAvailableGb: Int

    public init(ramTotalMb: Int, diskTotalGb: Int, diskAvailableGb: Int) {
        self.ramTotalMb = ramTotalMb
        self.diskTotalGb = diskTotalGb
        self.diskAvailableGb = diskAvailableGb
    }

    /// A reading with a zero total is a failed read in disguise; it never replaces good numbers.
    var ifUsable: MachineReading? { ramTotalMb > 0 && diskTotalGb > 0 ? self : nil }
}

extension SpaceBudget {
    /// Pure: the budget after a reading. A missing or unusable reading changes nothing.
    public func after(_ reading: MachineReading?) -> SpaceBudget {
        guard let usable = reading?.ifUsable else { return self }
        return withTotals(ramTotalMb: usable.ramTotalMb, diskTotalGb: usable.diskTotalGb)
    }
}
