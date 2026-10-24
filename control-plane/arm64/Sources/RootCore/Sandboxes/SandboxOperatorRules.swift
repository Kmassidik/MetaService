import Foundation

/// The parts of one sandbox the operator's rules read, so the rules need no store: whose it is, and where it stands.
public struct SandboxOwner: Equatable, Sendable {
    public let team: String
    public let state: SandboxState

    public init(team: String, state: SandboxState) {
        self.team = team
        self.state = state
    }

    /// Still at the helper: running, starting, or on its way in or out. A paused one is alive but holds nothing.
    public var isAlive: Bool { state.isAlive }
}

/// Which sandbox a request may touch. The public API acts for a key's team, so another team's sandbox is "no such sandbox"
/// and never a refusal that confirms it exists; the panel acts for the operator, who sees every team.
public enum SandboxOwnership {
    /// True when the request's team owns the sandbox and it has not ended.
    public static func permits(team: String, sandbox: SandboxOwner) -> Bool {
        sandbox.isAlive && team == sandbox.team
    }
}

/// What an operator may do to one sandbox from the panel.
public enum SandboxOperatorAction: String, CaseIterable, Sendable {
    case kill
    case pause
}

/// Why the panel will not act on a sandbox. The raw value is the panel's own error code, so the page can say it plainly.
public enum SandboxActionRefusal: String, Error, Equatable, Sendable {
    case noSuchSandbox = "not_found"
    case notPausable = "not_pausable"

    public var message: String {
        switch self {
        case .noSuchSandbox: return "No such sandbox, or it has already ended."
        case .notPausable: return "This sandbox is already paused."
        }
    }
}

/// The panel's action rules, checked before the helper is called so a wasted call never reaches a machine.
public enum SandboxPanelActions {
    /// What stops the operator's action on a sandbox, or nil when it may go ahead. A kill needs a sandbox that has not
    /// ended; a pause needs one that is not paused already, since a second pause would save nothing and confuse the record.
    public static func refusal(_ action: SandboxOperatorAction, sandbox: SandboxOwner) -> SandboxActionRefusal? {
        if !sandbox.isAlive { return .noSuchSandbox }
        if action == .pause && sandbox.state == .paused { return .notPausable }
        return nil
    }
}
