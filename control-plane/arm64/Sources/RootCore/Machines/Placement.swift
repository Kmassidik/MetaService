import Foundation

/// What the Root knows about a machine when it chooses where a workload goes (from its last heartbeat, minus what is already on the way).
public struct PlacementMachine: Equatable {
    public let id: String
    public let online: Bool
    public let capabilities: Capabilities?
    public let freeRamMb: Int
    public let freeDiskGb: Int
    public let hasProblems: Bool
    public let atMaxVMs: Bool
    /// The card's memory and how much of it is booked. Only read when the wish asks for a GPU memory limit.
    public let gpuRoom: GpuRoom

    public init(id: String, online: Bool, capabilities: Capabilities?, freeRamMb: Int, freeDiskGb: Int, hasProblems: Bool = false, atMaxVMs: Bool = false,
                gpuRoom: GpuRoom = GpuRoom(announcesLimit: false, totalGb: nil, bookedGb: 0)) {
        self.gpuRoom = gpuRoom
        self.hasProblems = hasProblems
        self.atMaxVMs = atMaxVMs
        self.id = id
        self.online = online
        self.capabilities = capabilities
        self.freeRamMb = freeRamMb
        self.freeDiskGb = freeDiskGb
    }
}

public struct PlacementRefusal: Error, Equatable {
    public let code: String
    public let message: String
    public let resource: String
    public let needed: Int
    public let free: Int

    public init(code: String, message: String, resource: String, needed: Int, free: Int) {
        self.code = code
        self.message = message
        self.resource = resource
        self.needed = needed
        self.free = free
    }
}

public struct PlacementWish: Equatable {
    public let kind: String
    public let gpuMode: String
    public let ramMb: Int
    public let diskGb: Int
    public let onlyMachine: String?
    /// The GPU memory limit asked for, in GB. Nil: no limit, nothing to book.
    public let gpuMemoryGb: Int?

    public init(kind: String, gpuMode: String, ramMb: Int, diskGb: Int, onlyMachine: String?, gpuMemoryGb: Int? = nil) {
        self.gpuMemoryGb = gpuMemoryGb
        self.kind = kind
        self.gpuMode = gpuMode
        self.ramMb = ramMb
        self.diskGb = diskGb
        self.onlyMachine = onlyMachine
    }
}

/// Picks the machine with the most room left after the workload, or says exactly why no machine can take it.
public enum Placement {
    public static func choose(_ machines: [PlacementMachine], _ wish: PlacementWish) throws -> String {
        let pool = machines.filter { wish.onlyMachine == nil || $0.id == wish.onlyMachine }
        guard !pool.isEmpty else { throw refusal("machine_not_found", "no such machine", "capability", 1, 0) }
        let online = pool.filter(\.online)
        guard !online.isEmpty else { throw refusal("no_machine_online", "no machine is online to take it", "capability", 1, 0) }
        let ready = online.filter { !$0.hasProblems }
        guard !ready.isEmpty else { throw refusal("machine_needs_setup", "the machine reports a problem that stops it from running workloads; see the machine in the panel", "capability", 1, 0) }
        let open = ready.filter { !$0.atMaxVMs }
        guard !open.isEmpty else { throw refusal("machine_at_max_vms", "every ready machine already runs the most VMs it was allowed", "capability", 1, 0) }
        let capable = open.filter { canRun($0, wish) }
        guard !capable.isEmpty else { throw refusal("missing_capability", noCapableMachineMessage(wish), "capability", 1, 0) }
        let bookable = try withRoomOnTheCard(capable, wish)
        let fitting = bookable.filter { $0.freeRamMb >= wish.ramMb && $0.freeDiskGb >= wish.diskGb }
        guard let best = fitting.max(by: { isBetter($1, than: $0, wish) }) else { throw shortage(capable, wish) }
        return best.id
    }

    static let noGpuContainerMessage = "No machine can share its GPU with a container: a machine needs an NVIDIA GPU and the NVIDIA container toolkit installed."
    static let noGpuVmMessage = "A VM cannot use the GPU yet: that needs virtualization turned on in the BIOS (SVM) and the card passed through to one VM."

    private static func noCapableMachineMessage(_ wish: PlacementWish) -> String {
        switch (wish.gpuMode, wish.kind) {
        case ("container", "container"): return noGpuContainerMessage
        case ("none", _): return "no machine can run a \(wish.kind)"
        default: return noGpuVmMessage
        }
    }

    private static func canRun(_ machine: PlacementMachine, _ wish: PlacementWish) -> Bool {
        guard let caps = machine.capabilities else { return false }
        guard wish.kind == "vm" ? caps.vm : caps.container else { return false }
        switch wish.gpuMode {
        case "container": return caps.gpuInContainer && wish.kind == "container"
        case "passthrough": return caps.gpuInVm && wish.kind == "vm"
        default: return true
        }
    }

    /// With a GPU memory limit asked for, only machines where it can be booked stay; when none can, the first machine's reason (by name) is the answer.
    private static func withRoomOnTheCard(_ capable: [PlacementMachine], _ wish: PlacementWish) throws -> [PlacementMachine] {
        guard let requested = wish.gpuMemoryGb else { return capable }
        let ordered = capable.sorted { $0.id < $1.id }
        let fitting = ordered.filter { GpuBooking.refusal($0.gpuRoom, requestedGb: requested) == nil }
        guard fitting.isEmpty else { return fitting }
        throw ordered.compactMap { GpuBooking.refusal($0.gpuRoom, requestedGb: requested) }.first ?? refusal("missing_capability", noGpuContainerMessage, "capability", 1, 0)
    }

    /// More room left after placing wins: RAM first, then disk, then the lower name, so the answer never changes between runs.
    private static func isBetter(_ one: PlacementMachine, than other: PlacementMachine, _ wish: PlacementWish) -> Bool {
        let left = (one.freeRamMb - wish.ramMb, one.freeDiskGb - wish.diskGb), right = (other.freeRamMb - wish.ramMb, other.freeDiskGb - wish.diskGb)
        guard left == right else { return left > right }
        return one.id < other.id
    }

    private static func shortage(_ capable: [PlacementMachine], _ wish: PlacementWish) -> PlacementRefusal {
        let roomiest = capable.max { ($0.freeRamMb, $0.freeDiskGb, $1.id) < ($1.freeRamMb, $1.freeDiskGb, $0.id) }!
        if roomiest.freeRamMb < wish.ramMb { return refusal("not_enough_room", "not enough RAM", "ram_mb", wish.ramMb, roomiest.freeRamMb) }
        return refusal("not_enough_room", "not enough disk", "disk_gb", wish.diskGb, roomiest.freeDiskGb)
    }

    private static func refusal(_ code: String, _ message: String, _ resource: String, _ needed: Int, _ free: Int) -> PlacementRefusal {
        PlacementRefusal(code: code, message: message, resource: resource, needed: needed, free: free)
    }
}
