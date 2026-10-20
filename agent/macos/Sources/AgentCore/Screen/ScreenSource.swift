import Foundation

/// Whether the Agent may capture and control this computer's screen right now.
public enum ScreenAccess: String, Equatable, Sendable {
    /// The operator did not allow screen control on this machine at install.
    case off
    /// Allowed, but the person at this computer has not given the permission macOS asks for (Screen Recording, Accessibility).
    case needsPermission = "needs_permission"
    case ready
}

public struct ScreenStatus: Equatable, Sendable {
    public let access: ScreenAccess
    public let width: Int
    public let height: Int
    /// What is missing, in plain words, when access is not ready.
    public let message: String?

    public init(access: ScreenAccess, width: Int = 0, height: Int = 0, message: String? = nil) {
        self.access = access
        self.width = width
        self.height = height
        self.message = message
    }
}

public struct ScreenFrame: Equatable, Sendable {
    public let contentType: String
    public let data: Data

    public init(contentType: String, data: Data) {
        self.contentType = contentType
        self.data = data
    }
}

public enum ScreenError: Error, Equatable {
    case notAllowed(String)
}

/// The screen of this computer: one implementation that really captures it, one that is simulated for tests, one that says no.
public protocol ScreenSource: Sendable {
    func status() async -> ScreenStatus
    func frame() async throws -> ScreenFrame
    func send(_ events: [ScreenInputEvent]) async throws
}

/// Used when screen control was not turned on for this machine.
public struct ScreenOff: ScreenSource {
    public init() {}
    public func status() async -> ScreenStatus { ScreenStatus(access: .off, message: "Screen control is not turned on for this computer.") }
    public func frame() async throws -> ScreenFrame { throw ScreenError.notAllowed("Screen control is not turned on for this computer.") }
    public func send(_ events: [ScreenInputEvent]) async throws { throw ScreenError.notAllowed("Screen control is not turned on for this computer.") }
}
