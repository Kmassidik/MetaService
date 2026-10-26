import Foundation

/// What the check can install for the person: the parts that a cross can be about.
public enum MissingPart: String, CaseIterable, Sendable {
    case vmTool = "vm_tool"
    case python
    /// NVIDIA's container toolkit, from NVIDIA's own package source. Only offered where an NVIDIA card was found.
    case gpuToolkit = "gpu_toolkit"
    /// qemu (what runs a full VM) and the KVM module, which is missing when `/dev/kvm` is missing. Not needed for containers.
    case vmPackages = "vm_packages"
    /// The registration that makes this computer's helper start again by itself at boot, so it is not offline after a restart until somebody runs `start.sh`.
    case autostart
}

public enum PackageManager: String, Sendable {
    case apt, dnf, pacman, zypper, apk
}

/// "Install it for me" is offered under a cross: which part it installs, and whether the person must type a password for sudo.
public struct InstallOffer: Encodable, Equatable {
    public let part: String
    public let needsPassword: Bool
}

public enum InstallOffers {
    /// "Starts at boot" is not a package: it is one file the system's own boot service reads, so a Mac with sudo is allowed as well as a Linux computer with apt.
    /// Everything else stays where the whole install is known and verified (see docs/PLAN-install-missing.md).
    public static func offer(for part: MissingPart, facts: RemoteFacts) -> InstallOffer? {
        guard needed(part, facts), canInstall(part, facts) else { return nil }
        return InstallOffer(part: part.rawValue, needsPassword: facts.sudo == .password)
    }

    /// Writing a file outside the home folder is the only privileged step, so a login with no sudo cannot do it. "Starts at boot" needs no package manager at all,
    /// which is why a Mac is allowed for it; everything else waits for the apt support the rest of the install has.
    private static func canInstall(_ part: MissingPart, _ facts: RemoteFacts) -> Bool {
        guard facts.sudo != .none else { return false }
        if part == .autostart, facts.isMac { return true }
        return facts.isLinux && facts.packageManager == .apt
    }

    /// True when that part really is missing on this computer: nothing is offered for a part that is already there.
    static func needed(_ part: MissingPart, _ facts: RemoteFacts) -> Bool {
        switch part {
        case .vmTool: return !facts.tools.contains("incus")
        case .python: return !facts.tools.contains("python3")
        case .gpuToolkit: return facts.nvidiaGpu != nil && !facts.hasGpuToolkit
        case .vmPackages: return facts.kvm == false || facts.qemu == false
        /// The check only answers this on a computer whose box it found, and the box has to be a path this parent can write a file for. A Mac installs Apple's
        /// container tool from a release, so it has no package manager: the fact there alone decides.
        case .autostart: return facts.autostart == false && RemoteInstallOptions.isPlainPath(facts.box)
        }
    }
}
