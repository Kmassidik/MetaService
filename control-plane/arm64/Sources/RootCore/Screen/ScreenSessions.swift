import Foundation

public enum ScreenMode: String, Equatable, Sendable {
    case view
    case control
}

public struct ScreenSession: Equatable, Sendable {
    public let ticket: String
    public let machine: String
    public let operatorName: String
    public internal(set) var mode: ScreenMode
    public let openedAt: Date
    public internal(set) var lastActivity: Date
}

public enum ScreenRefusal: Error, Equatable {
    case alreadyOpen
    case noSuchSession
    /// The session ended on its own: the text says why (idle or too long).
    case ended(String)
    case needsConfirm
    case viewOnly
}

/// The open screens: at most one per machine, each bound to the operator who opened it. A session ends after a quiet time or a maximum length,
/// and control needs a switch that is separate from opening. Pure: the clock and the ticket come in, nothing is read from the system.
public struct ScreenSessionBook: Sendable {
    public let idleSeconds: TimeInterval
    public let maxSeconds: TimeInterval
    private var sessions: [String: ScreenSession] = [:]

    public static let defaultIdleSeconds: TimeInterval = 600
    public static let defaultMaxSeconds: TimeInterval = 3600

    public init(idleSeconds: TimeInterval = defaultIdleSeconds, maxSeconds: TimeInterval = defaultMaxSeconds) {
        self.idleSeconds = idleSeconds
        self.maxSeconds = maxSeconds
    }

    /// A ticket is what the Root made: letters, digits, - and _ (the random text is base64url), and short.
    public static func isValidTicket(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 64 && text.unicodeScalars.allSatisfy { ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)))) || $0 == "-" || $0 == "_" }
    }

    public var open: [ScreenSession] { Array(sessions.values) }

    public mutating func open(machine: String, operatorName: String, ticket: String, now: Date) throws -> ScreenSession {
        dropEnded(now: now)
        guard !sessions.values.contains(where: { $0.machine == machine }) else { throw ScreenRefusal.alreadyOpen }
        let session = ScreenSession(ticket: ticket, machine: machine, operatorName: operatorName, mode: .view, openedAt: now, lastActivity: now)
        sessions[ticket] = session
        return session
    }

    /// Looks the session up for its owner and counts this as activity. A session that has ended is removed and refused.
    public mutating func use(ticket: String, operatorName: String, now: Date) throws -> ScreenSession {
        guard var session = sessions[ticket], session.operatorName == operatorName else { throw ScreenRefusal.noSuchSession }
        if let reason = endReason(session, now: now) {
            sessions[ticket] = nil
            throw ScreenRefusal.ended(reason)
        }
        session.lastActivity = now
        sessions[ticket] = session
        return session
    }

    public mutating func takeControl(ticket: String, operatorName: String, confirmed: Bool, now: Date) throws -> ScreenSession {
        guard confirmed else { throw ScreenRefusal.needsConfirm }
        _ = try use(ticket: ticket, operatorName: operatorName, now: now)
        sessions[ticket]?.mode = .control
        return sessions[ticket]!
    }

    @discardableResult
    public mutating func close(ticket: String, operatorName: String) -> ScreenSession? {
        guard let session = sessions[ticket], session.operatorName == operatorName else { return nil }
        sessions[ticket] = nil
        return session
    }

    /// Closes every session of a machine (it was removed, or its tunnel went away). Returns what was closed.
    @discardableResult
    public mutating func closeAll(machine: String) -> [ScreenSession] {
        let closing = sessions.values.filter { $0.machine == machine }
        for session in closing { sessions[session.ticket] = nil }
        return closing
    }

    private mutating func dropEnded(now: Date) {
        for session in sessions.values where endReason(session, now: now) != nil { sessions[session.ticket] = nil }
    }

    private func endReason(_ session: ScreenSession, now: Date) -> String? {
        if now.timeIntervalSince(session.openedAt) > maxSeconds { return "The session reached its maximum length." }
        if now.timeIntervalSince(session.lastActivity) > idleSeconds { return "The session was idle for too long." }
        return nil
    }
}
