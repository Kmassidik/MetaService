import Foundation

/// The files `autostart` touches, all inside the user's home or the box. A test gives it a dictionary.
public protocol AutostartFiles {
    func read(_ path: String) -> Data?
    func write(_ data: Data, to path: String) throws
    func remove(_ path: String) throws
    func processAlive(_ pid: Int32) -> Bool
}

public struct AutostartOutcome: Equatable {
    public let code: Int32
    public let lines: [String]
}

public struct AutostartProblem: Error, CustomStringConvertible, Equatable {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// `autostart on|off|status` on a Mac: a LaunchAgent in the login's own folder, loaded into its own `gui/<uid>` domain. No root, no sudo, nothing outside the home.
public struct AutostartService {
    public enum Action: String { case on, off, status }

    /// Everything is in place and will work after a reboot.
    public static let exitEffective: Int32 = 0
    /// The agent is written, but the owner has one step left (automatic login).
    public static let exitNeedsOwner: Int32 = 3
    static let launchctl = "/bin/launchctl"
    static let shell = "/bin/sh"
    static let startScript = "start.sh"
    static let autoLoginLine = "One step is left for the owner of this Mac: turn on automatic login for this user (System Settings, Users & Groups), so the helper can start after a restart without anyone signing in."
    static let autoLoginUnknownLine = "The helper cannot tell whether this Mac signs in by itself after a restart. The owner should check that automatic login is on for this user (System Settings, Users & Groups)."

    let files: AutostartFiles
    /// Runs a program and returns what it printed; throws when it fails. Tests record the calls.
    let run: BaselineChecks.Run
    let home: String
    let box: String
    let uid: UInt32

    public init(files: AutostartFiles, run: @escaping BaselineChecks.Run, home: String, box: String, uid: UInt32) {
        self.files = files
        self.run = run
        self.home = home
        self.box = box
        self.uid = uid
    }

    var plistPath: String { "\(home)/\(AutostartPlist.agentsFolder)/\(AutostartPlist.label).plist" }
    var service: String { "gui/\(uid)/\(AutostartPlist.label)" }

    public func perform(_ action: Action) async throws -> AutostartOutcome {
        switch action {
        case .on: return try await turnOn()
        case .off: return try await turnOff()
        case .status: return await status()
        }
    }

    private func turnOn() async throws -> AutostartOutcome {
        guard let script = files.read("\(box)/\(Self.startScript)") else { throw AutostartProblem("cannot read \(Self.startScript) in the MetaService folder") }
        let arguments = try AutostartPlist.startArguments(startScript: String(decoding: script, as: UTF8.self))
        let data = try AutostartPlist.plistData(box: box, arguments: arguments)
        let written = try writePlist(data)
        return await finish([written, try await loadIfNothingRuns()])
    }

    /// Writes the agent only when its content changed, so a second `on` touches nothing.
    private func writePlist(_ data: Data) throws -> String {
        guard files.read(plistPath) != data else { return "The start-at-login file was already in place." }
        try files.write(data, to: plistPath)
        return "Wrote the start-at-login file."
    }

    /// A helper already running (from start.sh, or from this agent) is left alone: a second copy would only fight it for the port.
    private func loadIfNothingRuns() async throws -> String {
        let alreadyThere = await loaded()
        guard !alreadyThere && !pidFileHelperAlive() else {
            return "A helper is already running, so none was started; the start-at-login file takes effect at the next login or restart."
        }
        do { _ = try await run(Self.launchctl, ["bootstrap", "gui/\(uid)", plistPath]) } catch {
            throw AutostartProblem("launchd did not accept the start-at-login file (is this login signed in?): \(error)")
        }
        return "No helper was running, so launchd started one."
    }

    /// After writing, the owner's step: automatic login, without which a LaunchAgent waits for someone to sign in.
    private func finish(_ lines: [String]) async -> AutostartOutcome {
        switch await autoLogin() {
        case true?: return AutostartOutcome(code: Self.exitEffective, lines: lines)
        case false?: return AutostartOutcome(code: Self.exitNeedsOwner, lines: lines + [Self.autoLoginLine])
        case nil: return AutostartOutcome(code: Self.exitNeedsOwner, lines: lines + [Self.autoLoginUnknownLine])
        }
    }

    private func turnOff() async throws -> AutostartOutcome {
        guard files.read(plistPath) != nil else { return AutostartOutcome(code: Self.exitEffective, lines: ["Start-at-login was not on; nothing to remove."]) }
        let wasLoaded = await loaded()
        if wasLoaded { _ = try? await run(Self.launchctl, ["bootout", service]) }
        try files.remove(plistPath)
        guard wasLoaded else { return AutostartOutcome(code: Self.exitEffective, lines: ["Start-at-login is off and its file is removed."]) }
        _ = try? await run(Self.shell, ["\(box)/\(Self.startScript)"])
        return AutostartOutcome(code: Self.exitEffective, lines: ["Start-at-login is off and its file is removed. The helper launchd ran was started again from start.sh."])
    }

    private func status() async -> AutostartOutcome {
        let written = files.read(plistPath) != nil
        let login = await autoLogin()
        let object: [String: Any] = ["unit_written": written, "loaded": await loaded(), "autologin": login as Any, "running_by_launchd": await runningByLaunchd(),
                                     "effective": written && login == true]
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return AutostartOutcome(code: Self.exitEffective, lines: [json])
    }

    // MARK: what the machine says

    private func loaded() async -> Bool { (try? await run(Self.launchctl, ["print", service])) != nil }

    private func runningByLaunchd() async -> Bool {
        guard let output = try? await run(Self.launchctl, ["print", service]) else { return false }
        return String(decoding: output, as: UTF8.self).contains("state = running")
    }

    private func autoLogin() async -> Bool? {
        guard let login = await BaselineChecks.exportDomain(BaselineChecks.loginWindowDomain, run: run) else { return nil }
        return login[BaselineChecks.autoLoginKey] is String
    }

    private func pidFileHelperAlive() -> Bool {
        guard let data = files.read("\(box)/\(AutostartPlist.pidFile)"), let pid = Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return files.processAlive(pid)
    }
}
