import Foundation

/// The "To fix" line for a part that is missing, for a person who installs it by hand. Every package command here is the one the system's own documentation gives
/// (Incus: linuxcontainers.org/incus/docs/main/installing/).
enum ManualFixes {
    static let incusDocs = "https://linuxcontainers.org/incus/docs/main/installing/"
    static let zabbly = "https://github.com/zabbly/incus"
    private static let afterIncus = "Then add the login user to the `incus-admin` group, run `sudo incus admin init --minimal`, and check again."

    static func vmTool(_ facts: RemoteFacts) -> String {
        if facts.isMac { return "Install Apple's container tool from https://github.com/apple/container/releases, then check again." }
        switch facts.packageManager {
        case .apt: return "Run `sudo apt install incus`. That works on Debian 13 and Ubuntu 24.04 or newer; an older one needs \(zabbly). \(afterIncus)"
        case .dnf: return "Run `sudo dnf install incus`. \(afterIncus)"
        case .pacman: return "Run `sudo pacman -S incus`. \(afterIncus)"
        case .zypper: return "Run `sudo zypper in incus`. \(afterIncus)"
        case .apk: return "Follow the Alpine steps at \(incusDocs) (the edge repositories, `apk add incus incus-client`, `rc-update add incusd`, `rc-service incusd start`). \(afterIncus)"
        case nil: return "Follow \(incusDocs) for this system. \(afterIncus)"
        }
    }

    static func python(_ facts: RemoteFacts) -> String {
        if facts.isMac { return "Install it with `xcode-select --install`, then check again." }
        switch facts.packageManager {
        case .dnf: return "Install it with `sudo dnf install python3`, then check again."
        case .pacman: return "Install it with `sudo pacman -S python`, then check again."
        case .zypper: return "Install it with `sudo zypper in python3`, then check again."
        case .apk: return "Install it with `apk add python3` (as root), then check again."
        case .apt, nil: return "Install it with `sudo apt install python3`, then check again."
        }
    }
}
