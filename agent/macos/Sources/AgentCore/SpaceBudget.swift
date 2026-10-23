import Foundation

/// Why a create was refused, with the numbers behind it.
public struct Refusal: Error, Equatable {
    public enum Code: String { case notEnoughRoom = "not_enough_room", missingCapability = "missing_capability" }
    public enum Resource: String { case ramMb = "ram_mb", diskGb = "disk_gb", capability }

    public let code: Code
    public let message: String
    public let resource: Resource
    public let needed: Int
    public let free: Int
}

/// How much of this machine MetaService may hand to workloads. All sizes are decided here, never read back from the OS,
/// because the OS counts caches and shared files differently from what a workload promised to use.
public struct SpaceBudget: Equatable {
    public private(set) var ramTotalMb: Int
    public private(set) var diskTotalGb: Int
    public var ramAllowanceMb: Int?
    public var diskAllowanceGb: Int?
    public var reserveRamMb: Int
    public var reserveDiskGb: Int
    public var marginDiskGb: Int
    /// True when the owner set the reserve explicitly; a re-read of the totals then leaves it alone.
    public let reserveRamPinned: Bool
    public let reserveDiskPinned: Bool

    public static let defaultMarginDiskGb = 20
    private static let minReserveRamMb = 4096
    private static let reserveRamDivisor = 4
    private static let minReserveDiskGb = 30
    private static let reserveDiskDivisor = 5

    private static func defaultReserveRamMb(_ total: Int) -> Int { max(minReserveRamMb, total / reserveRamDivisor) }
    private static func defaultReserveDiskGb(_ total: Int) -> Int { max(minReserveDiskGb, total / reserveDiskDivisor) }

    public init(ramTotalMb: Int, diskTotalGb: Int, ramAllowanceMb: Int? = nil, diskAllowanceGb: Int? = nil,
                reserveRamMb: Int? = nil, reserveDiskGb: Int? = nil, marginDiskGb: Int = SpaceBudget.defaultMarginDiskGb) {
        self.ramTotalMb = ramTotalMb
        self.diskTotalGb = diskTotalGb
        self.ramAllowanceMb = ramAllowanceMb
        self.diskAllowanceGb = diskAllowanceGb
        self.reserveRamMb = reserveRamMb ?? SpaceBudget.defaultReserveRamMb(ramTotalMb)
        self.reserveDiskGb = reserveDiskGb ?? SpaceBudget.defaultReserveDiskGb(diskTotalGb)
        self.marginDiskGb = marginDiskGb
        self.reserveRamPinned = reserveRamMb != nil
        self.reserveDiskPinned = reserveDiskGb != nil
    }

    /// The same budget over fresh machine totals. Default reserves follow the new totals; pinned (explicit) ones stay. Allowances stay and are clamped when used.
    public func withTotals(ramTotalMb: Int, diskTotalGb: Int) -> SpaceBudget {
        SpaceBudget(ramTotalMb: ramTotalMb, diskTotalGb: diskTotalGb, ramAllowanceMb: ramAllowanceMb, diskAllowanceGb: diskAllowanceGb,
                    reserveRamMb: reserveRamPinned ? reserveRamMb : nil, reserveDiskGb: reserveDiskPinned ? reserveDiskGb : nil, marginDiskGb: marginDiskGb)
    }

    /// RAM left for new workloads: the allowance, minus the host's reserve, minus workloads that are running.
    public func freeRamMb(workloads: [Workload]) -> Int {
        let running = workloads.filter { $0.state == .running || $0.state == .provisioning }.reduce(0) { $0 + $1.ramMb }
        return max(0, min(ramAllowanceMb ?? ramTotalMb, ramTotalMb) - reserveRamMb - running)
    }

    /// Disk left: every workload keeps its disk whether it runs or not.
    public func freeDiskGb(workloads: [Workload]) -> Int {
        let used = workloads.reduce(0) { $0 + $1.diskGb }
        return max(0, min(diskAllowanceGb ?? diskTotalGb, diskTotalGb) - reserveDiskGb - marginDiskGb - used)
    }

    /// Both checks. `osAvailableDiskGb` is what the file system says is really free; it can only make the answer stricter.
    public func check(_ request: CreateWorkloadRequest, workloads: [Workload], capabilities: Capabilities, osAvailableDiskGb: Int?) throws {
        try checkCapability(request, capabilities)
        let ram = freeRamMb(workloads: workloads)
        guard request.ramMb <= ram else { throw Refusal(code: .notEnoughRoom, message: "not enough RAM", resource: .ramMb, needed: request.ramMb, free: ram) }
        let disk = freeDiskGb(workloads: workloads)
        guard request.diskGb <= disk else { throw Refusal(code: .notEnoughRoom, message: "not enough disk", resource: .diskGb, needed: request.diskGb, free: disk) }
        guard let real = osAvailableDiskGb, request.diskGb + marginDiskGb > real else { return }
        throw Refusal(code: .notEnoughRoom, message: "the disk is fuller than the budget says", resource: .diskGb, needed: request.diskGb, free: max(0, real - marginDiskGb))
    }

    private func checkCapability(_ request: CreateWorkloadRequest, _ capabilities: Capabilities) throws {
        let canRun = request.kind == .vm ? capabilities.vm : capabilities.container
        guard canRun else { throw Refusal(code: .missingCapability, message: "this machine cannot run a \(request.kind.rawValue)", resource: .capability, needed: 1, free: 0) }
        let gpuOk: Bool
        switch request.gpuMode {
        case .none: gpuOk = true
        case .container: gpuOk = capabilities.gpuInContainer && request.kind == .container
        case .passthrough: gpuOk = capabilities.gpuInVm && request.kind == .vm
        }
        guard gpuOk else { throw Refusal(code: .missingCapability, message: "gpu mode \(request.gpuMode.rawValue) is not available here", resource: .capability, needed: 1, free: 0) }
    }
}
