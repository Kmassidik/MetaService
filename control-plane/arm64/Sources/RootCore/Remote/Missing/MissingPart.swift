import Foundation

/// What the check can install for the person: the parts that a cross can be about.
public enum MissingPart: String, CaseIterable, Sendable {
    case vmTool = "vm_tool"
    case python
    /// NVIDIA's container toolkit, from NVIDIA's own package source. Only offered where an NVIDIA card was found.
    case gpuToolkit = "gpu_toolkit"
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
    /// Only where the whole install is known and verified (see docs/PLAN-install-missing.md): a Linux computer with apt, where the login can use sudo.
    public static func offer(for part: MissingPart, facts: RemoteFacts) -> InstallOffer? {
        guard facts.isLinux, facts.packageManager == .apt, facts.sudo != .none else { return nil }
        if part == .gpuToolkit && facts.nvidiaGpu == nil { return nil }
        return InstallOffer(part: part.rawValue, needsPassword: facts.sudo == .password)
    }
}
