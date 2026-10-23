import Foundation
import RootCore

/// How the install ended, as the store keeps it. `waiting` puts the app back to "wanted, not started" (the VM was not running, or the helper gave no usable answer).
public enum AppFinish: Equatable {
    case ready(version: String?, installerSha256: String?)
    case failed(message: String, logTail: [String])
    case waiting

    public init(_ outcome: AppInstallOutcome) {
        switch outcome {
        case .installed(let version, let sha, _): self = .ready(version: version, installerSha256: sha)
        case .failed(let message, let logTail): self = .failed(message: message, logTail: logTail)
        case .helperTooOld: self = .failed(message: AppCatalog.oldHelperFailure, logTail: [])
        case .notDone: self = .waiting
        }
    }

    /// The audit word for an install that ended; nil for one that did not (it is tried again, so nothing is recorded yet).
    public var auditResult: String? {
        switch self {
        case .ready: return AppPhase.ready.rawValue
        case .failed: return AppPhase.failed.rawValue
        case .waiting: return nil
        }
    }

    public var installerSha256: String? {
        guard case .ready(_, let sha) = self else { return nil }
        return sha
    }
}
