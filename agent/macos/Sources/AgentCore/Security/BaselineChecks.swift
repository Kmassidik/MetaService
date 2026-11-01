import Foundation

/// The small checks of the baseline. Each one runs commands through the function the caller gives and reads files through `MacFiles`, so a test
/// needs no real Mac. Every check answers nil when it could not tell; nothing here needs root.
public protocol MacFiles {
    /// The names in a directory, or nil when it is missing or cannot be read.
    func list(_ directory: String) -> [String]?
    func read(_ path: String) -> Data?
}

public enum BaselineChecks {
    public typealias Run = CpuBrand.Run

    // MARK: firewall

    public static let firewallTool = "/usr/libexec/ApplicationFirewall/socketfilterfw"
    public static let firewallArguments = ["--getglobalstate"]
    private static let stateMarker = "State = "

    /// `Firewall is enabled. (State = 1)`: 0 is off, 1 and 2 (block all incoming) are on. Anything else, or a failed command, is nil.
    public static func firewall(run: Run) async -> Bool? {
        guard let output = try? await run(firewallTool, firewallArguments) else { return nil }
        let text = String(decoding: output, as: UTF8.self)
        guard let marker = text.range(of: stateMarker), let state = text[marker.upperBound...].first else { return nil }
        switch state {
        case "0": return false
        case "1", "2": return true
        default: return nil
        }
    }

    // MARK: automatic updates

    public static let defaultsTool = "/usr/bin/defaults"
    public static let softwareUpdateDomain = "/Library/Preferences/com.apple.SoftwareUpdate"
    public static let loginWindowDomain = "/Library/Preferences/com.apple.loginwindow"
    static let autoInstallKey = "AutomaticallyInstallMacOSUpdates"
    static let criticalInstallKey = "CriticalUpdateInstall"
    static let autoLoginKey = "autoLoginUser"

    /// The rule: true only when macOS updates install by themselves (AutomaticallyInstallMacOSUpdates = 1) and critical updates install by
    /// themselves (CriticalUpdateInstall = 1). When the settings can be read but either is missing or 0 it is false; when they cannot be read, nil.
    public static func autoUpdates(run: Run) async -> Bool? {
        guard let settings = await exportDomain(softwareUpdateDomain, run: run) else { return nil }
        return isOn(settings[autoInstallKey]) && isOn(settings[criticalInstallKey])
    }

    /// `defaults export <domain> -` gives the settings as a property list; nil when the command fails or the answer is not one.
    static func exportDomain(_ domain: String, run: Run) async -> [String: Any]? {
        guard let output = try? await run(defaultsTool, ["export", domain, "-"]) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: output, options: [], format: nil)) as? [String: Any]
    }

    private static func isOn(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        return (value as? NSNumber)?.intValue == 1
    }

    // MARK: starts after reboot

    public static let daemonsDirectory = "/Library/LaunchDaemons"
    public static let agentName = "metaservice-agent"
    private static let plistSuffix = ".plist"

    /// true when a launchd job for the helper starts it by itself (RunAtLoad or KeepAlive) after a reboot. A LaunchDaemon always does; a
    /// LaunchAgent only starts once someone is logged in, so it counts only when this Mac logs in automatically. false when there is no such job.
    /// nil when LaunchDaemons cannot be listed, or when a job in a LaunchAgents folder exists and the automatic-login setting cannot be read.
    public static func startsAfterReboot(files: MacFiles, homeDirectory: String, run: Run) async -> Bool? {
        guard let daemons = files.list(daemonsDirectory) else { return nil }
        if daemons.contains(where: { isStarterJob(files, daemonsDirectory + "/" + $0) }) { return true }
        let agentsDirectory = homeDirectory + "/Library/LaunchAgents"
        let agents = (files.list(agentsDirectory) ?? []).filter { isStarterJob(files, agentsDirectory + "/" + $0) }
        guard !agents.isEmpty else { return false }
        guard let login = await exportDomain(loginWindowDomain, run: run) else { return nil }
        return login[autoLoginKey] is String
    }

    private static func isStarterJob(_ files: MacFiles, _ path: String) -> Bool {
        guard path.hasSuffix(plistSuffix), let data = files.read(path) else { return false }
        guard let job = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { return false }
        return runsHelper(job) && startsByItself(job)
    }

    /// The job's program, or its label, is the helper.
    private static func runsHelper(_ job: [String: Any]) -> Bool {
        let program = (job["ProgramArguments"] as? [String])?.first ?? (job["Program"] as? String) ?? ""
        let label = job["Label"] as? String ?? ""
        return (program as NSString).lastPathComponent == agentName || label.contains(agentName)
    }

    private static func startsByItself(_ job: [String: Any]) -> Bool {
        if job["RunAtLoad"] as? Bool == true { return true }
        if let keep = job["KeepAlive"] as? Bool { return keep }
        return (job["KeepAlive"] as? [String: Any])?.isEmpty == false
    }
}
