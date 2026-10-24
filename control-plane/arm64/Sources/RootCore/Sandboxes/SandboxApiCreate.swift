import Foundation

/// A create that passed every check the parent can make without touching a machine: the id it will use, where it goes,
/// what it holds, and when it ends.
public struct SandboxCreatePlan: Equatable, Sendable {
    public let id: String
    public let template: String
    public let machine: String
    public let shape: SandboxShape
    public let endAt: Date

    public init(id: String, template: String, machine: String, shape: SandboxShape, endAt: Date) {
        self.id = id
        self.template = template
        self.machine = machine
        self.shape = shape
        self.endAt = endAt
    }
}

/// The order a create is checked in, kept pure so the order itself can be tested: the team's limits, then room on a machine,
/// then the end time. Only after all three does anything happen at a machine (see `sandbox/README.md`, "Risks": a create the
/// SDK retries must never leave a second sandbox running, so the cheapest refusals come first).
public enum SandboxApiCreate {
    /// v1 ships one template, `base`, at these sizes; a team cannot ask for bigger ones yet (the team's per-sandbox caps are
    /// not part of `TeamLimits`), so every sandbox gets this shape.
    public static let shape = SandboxShape()

    public static func plan(spec: SandboxCreateSpec, limits: TeamLimits, usage: TeamUsage,
                            machines: [SandboxMachine], createdAt: Date, id: String = SandboxIdentity.newId()) throws -> SandboxCreatePlan {
        if let refusal = SandboxLimits.refusal(limits, usage: usage, shape: shape) { throw SandboxApiFailure.teamLimit(refusal) }
        let machine = try placement(machines)
        return SandboxCreatePlan(id: id, template: spec.template, machine: machine, shape: shape,
                                 endAt: try endTime(createdAt: createdAt, timeoutSeconds: spec.timeoutSeconds))
    }

    private static func placement(_ machines: [SandboxMachine]) throws -> String {
        do {
            return try SandboxPlacement.choose(machines, shape: shape)
        } catch let refusal as SandboxPlacementRefusal {
            throw SandboxApiFailure.noRoom(refusal)
        }
    }

    private static func endTime(createdAt: Date, timeoutSeconds: Int) throws -> Date {
        do {
            return try SandboxEndTime.end(createdAt: createdAt, now: createdAt, timeoutSeconds: timeoutSeconds)
        } catch let refusal as SandboxEndTime.Refusal {
            throw SandboxApiFailure.endTime(refusal)
        }
    }
}
