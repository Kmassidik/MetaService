import Foundation

/// What "Connect" shows before anything is installed: the list of what the other computer has, and what the install could do there.
public struct RemoteVerification: Encodable, Equatable {
    public let requirements: [Requirement]
    public let canAdd: Bool
    /// The isolation levels possible there: "folder" always, "dedicated_user" when the login can use sudo.
    public let isolation: [String]
    public let system: String
}

/// Turns what a computer said about itself into the ✓ ! ✗ list. Read-only: nothing here changes any computer.
public enum RemoteVerify {
    public static let minimumRamMb = 4096
    public static let agentPort = 9101

    /// `parentURL` is where an Agent there will find the parent: its own loopback, through the SSH connection (see ParentUrl).
    public static func run(facts: RemoteFacts, fingerprint: String, agentBuilds: Set<String>, parentURL: String) -> RemoteVerification {
        let rows = [login(facts, fingerprint), system(facts), agent(facts, agentBuilds), memory(facts), disk(facts), vmSupport(facts), vmTool(facts), python(facts), admin(facts), port(facts), parent(parentURL)]
        let blocking = rows.filter { !$0.optional }
        return RemoteVerification(requirements: rows, canAdd: blocking.allSatisfy(\.ok), isolation: facts.sudo == .none ? ["folder"] : ["folder", "dedicated_user"],
                                  system: [facts.version, facts.chip, facts.arch].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    static func parent(_ url: String) -> Requirement {
        Requirement(id: "parent", label: "The parent can be reached from there", ok: true, optional: false, detail: "The Agent will report to \(url) there, which leads back through this SSH connection.")
    }

    static func login(_ facts: RemoteFacts, _ fingerprint: String) -> Requirement {
        Requirement(id: "login", label: "Login", ok: true, optional: false, detail: "Logged in as \(facts.user). Host key \(fingerprint).")
    }

    static func system(_ facts: RemoteFacts) -> Requirement {
        let known = (facts.isMac || facts.isLinux) && ["arm64", "aarch64", "x86_64"].contains(facts.arch)
        let named = [facts.version, facts.chip, facts.arch].filter { !$0.isEmpty }.joined(separator: " · ")
        return Requirement(id: "system", label: "System", ok: known, optional: false, detail: known ? named : "\(facts.os) on \(facts.arch) is not supported. MetaService runs on macOS and Linux (x86_64 or ARM).")
    }

    static func agent(_ facts: RemoteFacts, _ builds: Set<String>) -> Requirement {
        let have = builds.contains(facts.agentBuild)
        return Requirement(id: "agent", label: "MetaService program for this system", ok: have, optional: false,
                           detail: have ? "Found (\(facts.agentBuild))." : "The parent has no MetaService program for \(facts.agentBuild) yet, so it cannot be installed there.")
    }

    static func memory(_ facts: RemoteFacts) -> Requirement {
        let ram = facts.ramMb ?? 0
        let enough = ram >= minimumRamMb
        return Requirement(id: "memory", label: "Memory", ok: enough, optional: true,
                           detail: facts.ramMb == nil ? "Could not read it." : enough ? "\(ram / 1024) GB." : "\(ram) MB; VMs need at least \(minimumRamMb / 1024) GB.")
    }

    static func disk(_ facts: RemoteFacts) -> Requirement {
        let free = facts.diskFreeGb ?? 0
        let enough = free >= ComputerChecks.minimumFreeDiskGb
        return Requirement(id: "disk", label: "Free disk space", ok: enough, optional: true,
                           detail: facts.diskFreeGb == nil ? "Could not read it." : enough ? "\(free) GB free." : "\(free) GB free; VMs need at least \(ComputerChecks.minimumFreeDiskGb) GB.")
    }

    static func vmSupport(_ facts: RemoteFacts) -> Requirement {
        if facts.isMac {
            let apple = ["arm64", "aarch64"].contains(facts.arch)
            return Requirement(id: "vm_support", label: "Can run VMs", ok: apple, optional: true, detail: apple ? "Apple Silicon can." : "Apple's container tool needs Apple Silicon.")
        }
        let kvm = facts.kvm == true
        return Requirement(id: "vm_support", label: "Can run VMs", ok: kvm, optional: true, detail: kvm ? "/dev/kvm is there." : "There is no /dev/kvm, so VMs cannot run (containers still can).")
    }

    static func vmTool(_ facts: RemoteFacts) -> Requirement {
        let tool = facts.isMac ? "container" : "incus"
        let label = facts.isMac ? "Apple's container tool (makes the VMs)" : "Incus (makes the VMs)"
        let found = facts.tools.contains(tool)
        return Requirement(id: "vm_tool", label: label, ok: found, optional: true,
                           detail: found ? "Installed. It is used as it is; nothing about it is changed." : "Not installed. The install can add it, only if you tick \"Install the VM tool too\".")
    }

    static func python(_ facts: RemoteFacts) -> Requirement {
        let found = facts.tools.contains("python3")
        return Requirement(id: "python", label: "Python (runs the chat)", ok: found, optional: true, detail: found ? "Found." : "Not installed. Without it the chat cannot run there.")
    }

    static func admin(_ facts: RemoteFacts) -> Requirement {
        switch facts.sudo {
        case .passwordless: return Requirement(id: "admin", label: "Admin rights (sudo)", ok: true, optional: true, detail: "Yes. The engine can get its own user.")
        case .password: return Requirement(id: "admin", label: "Admin rights (sudo)", ok: true, optional: true, detail: "Yes, with a password. The engine can get its own user.")
        case .none: return Requirement(id: "admin", label: "Admin rights (sudo)", ok: false, optional: true, detail: "No. The engine goes in a folder of \(facts.user) instead of getting its own user.")
        }
    }

    static func port(_ facts: RemoteFacts) -> Requirement {
        switch facts.port9101Free {
        case .some(true) where facts.port9101Ours: return Requirement(id: "port", label: "Port \(agentPort) free", ok: true, optional: false, detail: "MetaService's own program from an earlier install is running there. Adding the computer replaces it.")
        case .some(true): return Requirement(id: "port", label: "Port \(agentPort) free", ok: true, optional: false, detail: "Nothing uses it.")
        case .some(false): return Requirement(id: "port", label: "Port \(agentPort) free", ok: false, optional: false, detail: "Something already listens on \(agentPort). Stop it first, or MetaService cannot start there.")
        case .none: return Requirement(id: "port", label: "Port \(agentPort) free", ok: true, optional: true, detail: "Could not check it.")
        }
    }
}
