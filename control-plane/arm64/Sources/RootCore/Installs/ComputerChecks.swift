import Foundation

/// One thing a computer needs before MetaService can do its whole job, and whether it has it.
public struct Requirement: Encodable, Equatable {
    public let id: String
    public let label: String
    public let ok: Bool
    /// Whether the install can finish without it: false means the install itself cannot work.
    public let optional: Bool
    /// What was found, or what is missing and what that means, in plain words.
    public let detail: String
}

/// The "is this computer ready?" check the Add machine form shows before anything is installed. Pure: the caller says what exists and how much room is free.
public enum ComputerChecks {
    /// Where the Mac Agent looks for Apple's container tool (it must stay the same list as `ProcessContainerCLI.searchPaths` in the Agent).
    public static let containerPaths = ["/usr/local/bin/container", "/opt/homebrew/bin/container", "/usr/bin/container"]
    /// Where the Mac Agent looks for Python, which runs the chat (the same list as the Agent's chat supervisor).
    public static let pythonPaths = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
    /// Room a first VM image and its disk need at the least.
    public static let minimumFreeDiskGb = 20

    public static func run(agentReady: Bool, freeDiskGb: Int, exists: (String) -> Bool) -> [Requirement] {
        [agent(agentReady), containerTool(exists), python(exists), room(freeDiskGb)]
    }

    static func agent(_ ready: Bool) -> Requirement {
        Requirement(id: "agent", label: "MetaService program", ok: ready, optional: false,
                    detail: ready ? "Found." : "Not built yet. Run ./install.sh, which builds it.")
    }

    static func containerTool(_ exists: (String) -> Bool) -> Requirement {
        let found = containerPaths.first(where: exists)
        return Requirement(id: "container", label: "Apple's container tool (makes the VMs)", ok: found != nil, optional: true,
                           detail: found.map { "Found at \($0)." } ?? "Not installed. MetaService can be installed without it, but this computer cannot create VMs until it is.")
    }

    static func python(_ exists: (String) -> Bool) -> Requirement {
        let found = pythonPaths.first(where: exists)
        return Requirement(id: "python", label: "Python (runs the chat)", ok: found != nil, optional: true,
                           detail: found.map { "Found at \($0)." } ?? "Not installed. Without it the chat cannot run on this computer.")
    }

    static func room(_ freeGb: Int) -> Requirement {
        let enough = freeGb >= minimumFreeDiskGb
        return Requirement(id: "disk", label: "Free disk space", ok: enough, optional: true,
                           detail: enough ? "\(freeGb) GB free." : "\(freeGb) GB free; VMs need at least \(minimumFreeDiskGb) GB.")
    }
}
