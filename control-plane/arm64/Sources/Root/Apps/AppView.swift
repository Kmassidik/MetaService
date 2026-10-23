import Foundation
import RootCore

/// What the panel sees of the app in one VM. Every part is null or empty when it is not known, so the shape never changes.
/// The installer's checksum stays on the parent (it goes to the audit trail only).
struct AppView: Encodable {
    let app: String?
    let state: String
    let message: String?
    let logTail: [String]
    let version: String?
    let startedAt: Int?

    enum CodingKeys: String, CodingKey { case app, state, message, logTail, version, startedAt }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(app, forKey: .app)
        try box.encode(state, forKey: .state)
        try box.encode(message, forKey: .message)
        try box.encode(logTail, forKey: .logTail)
        try box.encode(version, forKey: .version)
        try box.encode(startedAt, forKey: .startedAt)
    }

    static let none = AppView(app: nil, state: AppPhase.none.rawValue, message: nil, logTail: [], version: nil, startedAt: nil)

    /// The record as it reads at `now` (an install that never ended reads as failed).
    init(_ stored: AppRecord, at now: Int) {
        let record = stored.atTime(now)
        self.init(app: record.app, state: record.phase.rawValue, message: record.message, logTail: record.logTail, version: record.version, startedAt: record.startedAt)
    }

    private init(app: String?, state: String, message: String?, logTail: [String], version: String?, startedAt: Int?) {
        self.app = app
        self.state = state
        self.message = message
        self.logTail = logTail
        self.version = version
        self.startedAt = startedAt
    }
}
