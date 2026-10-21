import Foundation

/// What "Connect" shows before anything is installed: the list of what the other computer has, and what the install could do there.
public struct RemoteVerification: Encodable, Equatable {
    public let requirements: [Requirement]
    public let canAdd: Bool
    /// The isolation levels possible there: "folder" always, "dedicated_user" when the login can use sudo.
    public let isolation: [String]
    public let system: String
}

/// Turns what a computer said about itself into the ✓ ✗ list: a computer can be added only when every row is ✓, and every ✗ says what to do. Read-only: nothing here changes any computer.
public enum RemoteVerify {
    public static let minimumRamMb = 4096
    public static let agentPort = 9101
    /// Rows whose cross does not stop the computer from being added: the computer works without them, only one feature does not.
    static let optionalRows: Set<String> = [gpuToolkitRow]
    static let gpuToolkitRow = "gpu_toolkit"

    /// `parentURL` is where an Agent there will find the parent: its own loopback, through the SSH connection (see ParentUrl).
    public static func run(facts: RemoteFacts, fingerprint: String, agentBuilds: Set<String>, parentURL: String) -> RemoteVerification {
        guard !facts.isWindows else { return windows(facts, fingerprint) }
        let rows = [login(facts, fingerprint), system(facts), agent(facts, agentBuilds), memory(facts), disk(facts), vmSupport(facts), vmTool(facts)] + gpuToolkit(facts)
            + [python(facts), admin(facts), port(facts), parent(parentURL)]
        return RemoteVerification(requirements: rows, canAdd: rows.filter { !optionalRows.contains($0.id) }.allSatisfy(\.ok), isolation: facts.sudo == .none ? ["folder"] : ["folder", "dedicated_user"],
                                  system: [facts.version, facts.chip, facts.arch].filter { !$0.isEmpty }.joined(separator: " · "))
    }

    /// Windows has no helper program and the check itself is a shell script, so there is nothing more to ask: one cross that says why.
    private static func windows(_ facts: RemoteFacts, _ fingerprint: String) -> RemoteVerification {
        let rows = [login(facts, fingerprint), Requirement(id: "system", label: "System", ok: false, detail: "Windows is not supported yet. MetaService's check and its helper program are made for macOS and Linux; there is no Windows helper.",
                                                          fix: "Use a Mac or a Linux computer (x86_64 or ARM).")]
        return RemoteVerification(requirements: rows, canAdd: false, isolation: [], system: facts.os)
    }

    static func parent(_ url: String) -> Requirement {
        Requirement(id: "parent", label: "The parent can be reached from there", ok: true, detail: "The Agent will report to \(url) there, which leads back through this SSH connection.")
    }

    static func login(_ facts: RemoteFacts, _ fingerprint: String) -> Requirement {
        Requirement(id: "login", label: "Login", ok: true, detail: "Logged in as \(facts.user). Host key \(fingerprint).")
    }

    static func system(_ facts: RemoteFacts) -> Requirement {
        let known = (facts.isMac || facts.isLinux) && ["arm64", "aarch64", "x86_64"].contains(facts.arch)
        let named = [facts.version, facts.chip, facts.arch].filter { !$0.isEmpty }.joined(separator: " · ")
        return Requirement(id: "system", label: "System", ok: known, detail: known ? named : "\(facts.os) on \(facts.arch) is not supported. MetaService runs on macOS and Linux (x86_64 or ARM).",
                           fix: "Use a Mac or a Linux computer (x86_64 or ARM).")
    }

    static func agent(_ facts: RemoteFacts, _ builds: Set<String>) -> Requirement {
        let have = builds.contains(facts.agentBuild)
        return Requirement(id: "agent", label: "MetaService program for this system", ok: have,
                           detail: have ? "Found (\(facts.agentBuild))." : "The parent has no MetaService program for \(facts.agentBuild) yet, so it cannot be installed there.",
                           fix: missingProgramFix(facts))
    }

    /// Linux programs come from one script on the parent's computer; a Mac program is built there by hand.
    private static func missingProgramFix(_ facts: RemoteFacts) -> String {
        guard facts.isLinux else {
            return "Build the \(facts.agentBuild) program on the parent's side and put it in the parent's state/agent-builds folder, then check again."
        }
        return "Run scripts/build-linux-helpers.sh on the parent's computer, then check again."
    }

    static func memory(_ facts: RemoteFacts) -> Requirement {
        let ram = facts.ramMb ?? 0
        let enough = ram >= minimumRamMb
        return Requirement(id: "memory", label: "Memory", ok: enough,
                           detail: facts.ramMb == nil ? "Could not read it." : enough ? "\(ram / 1024) GB." : "\(ram) MB; VMs need at least \(minimumRamMb / 1024) GB.",
                           fix: facts.ramMb == nil ? "Check again. If it keeps failing, run `\(facts.isMac ? "sysctl hw.memsize" : "free -m")` on that computer to see why." : "Use a computer with at least \(minimumRamMb / 1024) GB of memory.")
    }

    static func disk(_ facts: RemoteFacts) -> Requirement {
        let free = facts.diskFreeGb ?? 0
        let enough = free >= ComputerChecks.minimumFreeDiskGb
        return Requirement(id: "disk", label: "Free disk space", ok: enough,
                           detail: facts.diskFreeGb == nil ? "Could not read it." : enough ? "\(free) GB free." : "\(free) GB free; VMs need at least \(ComputerChecks.minimumFreeDiskGb) GB.",
                           fix: facts.diskFreeGb == nil ? "Check again. If it keeps failing, run `df -h ~` on that computer to see why." : "Free up space on that computer until at least \(ComputerChecks.minimumFreeDiskGb) GB is free.")
    }

    static func vmSupport(_ facts: RemoteFacts) -> Requirement {
        if facts.isMac {
            let apple = ["arm64", "aarch64"].contains(facts.arch)
            return Requirement(id: "vm_support", label: "Can run VMs", ok: apple, detail: apple ? "Apple Silicon can." : "Apple's container tool needs Apple Silicon.",
                               fix: "Use a Mac with Apple Silicon (M1 or newer).")
        }
        let kvm = facts.kvm == true
        let detail = kvm ? "/dev/kvm is there: VMs and containers." : "Containers only: there is no /dev/kvm, so full VMs cannot run (they need virtualization turned on in the BIOS)."
        return Requirement(id: "vm_support", label: "Can run workloads", ok: true, detail: detail)
    }

    static func vmTool(_ facts: RemoteFacts) -> Requirement {
        let tool = facts.isMac ? "container" : "incus"
        let label = facts.isMac ? "Apple's container tool (makes the VMs)" : "Incus (makes the VMs)"
        let found = facts.tools.contains(tool)
        return Requirement(id: "vm_tool", label: label, ok: found, detail: found ? "Installed. It is used as it is; nothing about it is changed." : "Not installed. MetaService needs it to make VMs.",
                           fix: ManualFixes.vmTool(facts), install: InstallOffers.offer(for: .vmTool, facts: facts))
    }

    /// Only for a Linux computer with an NVIDIA card: without NVIDIA's container toolkit a container cannot use the card. Not needed to add the computer.
    static func gpuToolkit(_ facts: RemoteFacts) -> [Requirement] {
        guard facts.isLinux, let card = facts.nvidiaGpu else { return [] }
        let found = facts.hasGpuToolkit
        return [Requirement(id: gpuToolkitRow, label: "NVIDIA container toolkit (lets containers use the GPU)", ok: found,
                            detail: found ? "Installed. Containers can share the \(card)." : "Not installed. This computer has an NVIDIA GPU (\(card)) but containers cannot use it yet. You can add the computer without it.",
                            fix: ManualFixes.gpuToolkit(facts), install: InstallOffers.offer(for: .gpuToolkit, facts: facts))]
    }

    static func python(_ facts: RemoteFacts) -> Requirement {
        let found = facts.tools.contains("python3")
        return Requirement(id: "python", label: "Python (runs the chat)", ok: found, detail: found ? "Found." : "Not installed. Without it the chat cannot run there.",
                           fix: ManualFixes.python(facts), install: InstallOffers.offer(for: .python, facts: facts))
    }

    /// Having sudo is not a requirement: without it the engine lives in a folder of the login user. Both answers are fine, only the sentence differs.
    static func admin(_ facts: RemoteFacts) -> Requirement {
        let detail: String
        switch facts.sudo {
        case .passwordless: detail = "Yes. The engine can get its own user."
        case .password: detail = "Yes, with a password. The engine can get its own user."
        case .none: detail = "No. The engine goes in a folder of \(facts.user) instead of getting its own user."
        }
        return Requirement(id: "admin", label: "Admin rights (sudo)", ok: true, detail: detail)
    }

    static func port(_ facts: RemoteFacts) -> Requirement {
        let label = "Port \(agentPort) free"
        switch facts.port9101Free {
        case .some(true) where facts.port9101Ours: return Requirement(id: "port", label: label, ok: true, detail: "MetaService's own program from an earlier install is running there. Adding the computer replaces it.")
        case .some(true): return Requirement(id: "port", label: label, ok: true, detail: "Nothing uses it.")
        case .some(false): return Requirement(id: "port", label: label, ok: false, detail: "Something already listens on \(agentPort). Stop it first, or MetaService cannot start there.",
                                              fix: "Stop what uses port \(agentPort) there (`ss -ltnp | grep \(agentPort)` shows what it is), then check again.")
        case .none: return Requirement(id: "port", label: label, ok: true, detail: "Could not check it.")
        }
    }
}
