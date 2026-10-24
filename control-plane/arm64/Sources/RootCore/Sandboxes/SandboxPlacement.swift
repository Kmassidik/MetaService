import Foundation

/// What the Root knows about one machine when it places a sandbox: whether it says it can run sandboxes, whether it is
/// online, and the room its helper last reported (`Facts.sandbox` in contract/openapi.yaml).
public struct SandboxMachine: Equatable {
    public let id: String
    public let online: Bool
    public let capabilities: Capabilities?
    public let facts: SandboxFacts?

    public init(id: String, online: Bool, capabilities: Capabilities?, facts: SandboxFacts?) {
        self.id = id
        self.online = online
        self.capabilities = capabilities
        self.facts = facts
    }
}

/// Why no machine can take a sandbox of this shape.
public struct SandboxPlacementRefusal: Error, Equatable {
    public let code: String
    public let message: String
    /// `capability`, `slots`, `vcpu`, `ram_mb` or `disk_mb`.
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

/// Picks the machine a sandbox goes on, among those that say they can run sandboxes. Pure: the machines and the shape
/// come in, one id or a refusal goes out.
///
/// A machine qualifies when `capabilities.sandbox` is true, its helper sent `Facts.sandbox`, it is online, it has a free
/// running slot, and its booked vCPU, memory and disk plus the shape fit within its max. Among those, the least booked
/// wins (memory, then vCPU, then disk, then the lower id), so the answer never changes between runs and sandboxes spread
/// out instead of piling onto the first machine.
public enum SandboxPlacement {
    public static let noSandboxMachineCode = "no_sandbox_machine"
    public static let noMachineOnlineCode = "no_machine_online"
    public static let noRoomCode = "not_enough_room"

    public static let capabilityResource = "capability"
    public static let slotsResource = "slots"
    public static let vcpuResource = "vcpu"
    public static let ramResource = "ram_mb"
    public static let diskResource = "disk_mb"

    public static func choose(_ machines: [SandboxMachine], shape: SandboxShape) throws -> String {
        let capable = machines.compactMap(Candidate.init)
        guard !capable.isEmpty else {
            throw refusal(noSandboxMachineCode, "No machine can run sandboxes yet.", capabilityResource, 1, 0)
        }
        let online = capable.filter(\.machine.online)
        guard !online.isEmpty else {
            throw refusal(noMachineOnlineCode, "Every machine that can run sandboxes is offline.", capabilityResource, 1, 0)
        }
        let fitting = online.filter { fits($0.facts, shape) }
        guard let best = fitting.min(by: isLessBooked) else { throw shortage(online, shape) }
        return best.machine.id
    }

    /// A machine that advertises sandboxes and says what it has room for.
    private struct Candidate {
        let machine: SandboxMachine
        let facts: SandboxFacts

        init?(_ machine: SandboxMachine) {
            guard machine.capabilities?.sandbox == true, let facts = machine.facts else { return nil }
            self.machine = machine
            self.facts = facts
        }
    }

    private static func fits(_ facts: SandboxFacts, _ shape: SandboxShape) -> Bool {
        facts.running < facts.maxRunning
            && facts.booked.vcpu + shape.vcpu <= facts.maxVcpu
            && facts.booked.ramMb + shape.ramMb <= facts.maxRamMb
            && facts.booked.diskMb + shape.diskMb <= facts.maxDiskMb
    }

    /// Least booked first, with the id as the stable last word.
    private static func isLessBooked(_ one: Candidate, than other: Candidate) -> Bool {
        let left = one.facts.booked, right = other.facts.booked
        if left.ramMb != right.ramMb { return left.ramMb < right.ramMb }
        if left.vcpu != right.vcpu { return left.vcpu < right.vcpu }
        if left.diskMb != right.diskMb { return left.diskMb < right.diskMb }
        return one.machine.id < other.machine.id
    }

    /// Every online machine was short of something. A machine with a free running slot, if there is one, says which
    /// resource; when none has a slot left, that is the answer. The roomiest such machine gives the numbers.
    private static func shortage(_ online: [Candidate], _ shape: SandboxShape) -> SandboxPlacementRefusal {
        let withSlot = online.filter { $0.facts.running < $0.facts.maxRunning }
        guard !withSlot.isEmpty else {
            let most = online.map { max(0, $0.facts.maxRunning - $0.facts.running) }.max() ?? 0
            return refusal(noRoomCode, "Every machine is already running as many sandboxes as it allows.", slotsResource, 1, most)
        }
        guard let candidate = withSlot.max(by: { isRoomier($1, than: $0) }) else {
            return refusal(noRoomCode, "No machine has room for this sandbox right now.", capabilityResource, 1, 0)
        }
        let facts = candidate.facts
        let vcpu = max(0, facts.maxVcpu - facts.booked.vcpu)
        let ramMb = max(0, facts.maxRamMb - facts.booked.ramMb)
        let diskMb = max(0, facts.maxDiskMb - facts.booked.diskMb)
        if vcpu < shape.vcpu {
            return refusal(noRoomCode, "No machine has \(shape.vcpu) vCPU free for this sandbox.", vcpuResource, shape.vcpu, vcpu)
        }
        if ramMb < shape.ramMb {
            return refusal(noRoomCode, "No machine has \(shape.ramMb) MB of memory free for this sandbox.", ramResource, shape.ramMb, ramMb)
        }
        return refusal(noRoomCode, "No machine has \(shape.diskMb) MB of disk free for this sandbox.", diskResource, shape.diskMb, diskMb)
    }

    /// Which of two machines has more left of everything; the id breaks a tie, so the pick is stable.
    private static func isRoomier(_ one: Candidate, than other: Candidate) -> Bool {
        let left = (freeRam(one.facts), freeVcpu(one.facts), freeDisk(one.facts))
        let right = (freeRam(other.facts), freeVcpu(other.facts), freeDisk(other.facts))
        if left != right { return left > right }
        return one.machine.id < other.machine.id
    }

    private static func freeRam(_ facts: SandboxFacts) -> Int { max(0, facts.maxRamMb - facts.booked.ramMb) }
    private static func freeVcpu(_ facts: SandboxFacts) -> Int { max(0, facts.maxVcpu - facts.booked.vcpu) }
    private static func freeDisk(_ facts: SandboxFacts) -> Int { max(0, facts.maxDiskMb - facts.booked.diskMb) }

    private static func refusal(_ code: String, _ message: String, _ resource: String, _ needed: Int, _ free: Int) -> SandboxPlacementRefusal {
        SandboxPlacementRefusal(code: code, message: message, resource: resource, needed: needed, free: free)
    }
}
