import Foundation

/// A refusal of the public sandbox API, in E2B's error shape: `{ "code": <status>, "message": ..., "error_code": ... }`.
///
/// The shape is not the panel's (`{"error": {"code", "message"}}` on purpose: the SDKs check `code` against the HTTP
/// status and turn 401, 429 and 503 into their own error types, so every refusal here repeats the status in the body.
public struct SandboxApiFailure: Error, Equatable, Sendable {
    /// The HTTP status, repeated in the body as `code`.
    public let status: Int
    /// What went wrong, in plain words. Never carries a key, a token or anything else secret.
    public let message: String
    /// A short code for programs, or nil when the plain status says it all.
    public let errorCode: String?

    public init(status: Int, message: String, errorCode: String? = nil) {
        self.status = status
        self.message = message
        self.errorCode = errorCode
    }
}

/// The codes this API answers with, named once so the routes and their tests agree.
public enum SandboxApiCodes {
    public static let invalidKey = "invalid_key"
    public static let revokedKey = "revoked_key"
    public static let sessionCookie = "session_cookie"
    public static let rateLimited = "rate_limited"
    public static let invalidRequest = "invalid_request"
    public static let unsupported = "unsupported"
    public static let notFound = "not_found"
    public static let teamLimit = "team_limit"
    public static let noRoom = "no_room"
    public static let machineUnreachable = "machine_unreachable"
    public static let startTimeout = "start_timeout"
    public static let helperRefused = "helper_refused"
    public static let notPausable = "not_pausable"
}

extension SandboxApiFailure {
    // MARK: who is calling

    /// No key, a key that is not one of ours, or a key sent alongside a session cookie.
    public static let missingKey = SandboxApiFailure(status: 401, message: "This API needs an API key in Authorization: Bearer <key> or X-API-Key.", errorCode: SandboxApiCodes.invalidKey)
    public static let revokedKey = SandboxApiFailure(status: 401, message: "This API key was revoked.", errorCode: SandboxApiCodes.revokedKey)
    /// A browser (or a page) sent its cookies. See `SandboxApiAuth` for why that is refused rather than ignored.
    public static let sessionCookie = SandboxApiFailure(status: 401, message: "This API takes an API key and never a session cookie.", errorCode: SandboxApiCodes.sessionCookie)
    public static let tooMany = SandboxApiFailure(status: 429, message: "Too many requests; try again shortly.", errorCode: SandboxApiCodes.rateLimited)

    // MARK: the request

    public static func invalid(_ message: String) -> SandboxApiFailure {
        SandboxApiFailure(status: 400, message: message, errorCode: SandboxApiCodes.invalidRequest)
    }

    /// A field we do not support yet. Refused rather than ignored, so a program never gets weaker rules than it asked for.
    public static func unsupported(_ message: String) -> SandboxApiFailure {
        SandboxApiFailure(status: 400, message: message, errorCode: SandboxApiCodes.unsupported)
    }

    public static func noSuchSandbox() -> SandboxApiFailure {
        SandboxApiFailure(status: 404, message: "No such sandbox, or not this team's.", errorCode: SandboxApiCodes.notFound)
    }

    // MARK: the parent's own refusals

    /// A team's limit: too many at once and too many per hour are the SDK's rate limit (it retries), a size is a plain refusal.
    public static func teamLimit(_ refusal: TeamLimitRefusal) -> SandboxApiFailure {
        let status = (refusal.reason == .tooManyRunning || refusal.reason == .tooManyPerHour) ? 429 : 403
        return SandboxApiFailure(status: status, message: refusal.message, errorCode: SandboxApiCodes.teamLimit)
    }

    /// No machine can take it right now. 503, because the SDK retries that and nothing is left running behind.
    public static func noRoom(_ refusal: SandboxPlacementRefusal) -> SandboxApiFailure {
        SandboxApiFailure(status: 503, message: refusal.message, errorCode: SandboxApiCodes.noRoom)
    }

    /// A timeout this sandbox may not have: 403, as the API says for a life over the team's longest.
    public static func endTime(_ refusal: SandboxEndTime.Refusal) -> SandboxApiFailure {
        SandboxApiFailure(status: 403, message: refusal.message, errorCode: SandboxApiCodes.teamLimit)
    }

    // MARK: the helper

    /// What the helper said, as the SDK understands it. An unreachable helper and a helper that ran out of room are both a
    /// 503: nothing was recorded, so the SDK's retry starts clean.
    public static func helper(status: Int, errorCode: String?, message: String?) -> SandboxApiFailure {
        switch status {
        case 404:
            return SandboxApiFailure(status: 503, message: "This machine's helper does not run sandboxes yet.", errorCode: SandboxApiCodes.machineUnreachable)
        case 409:
            return SandboxApiFailure(status: 409, message: message ?? "The machine refused this sandbox.", errorCode: errorCode ?? SandboxApiCodes.helperRefused)
        case 504:
            return SandboxApiFailure(status: 503, message: message ?? "The sandbox did not get ready in time; it was removed.", errorCode: SandboxApiCodes.startTimeout)
        case 400:
            return SandboxApiFailure(status: 400, message: message ?? "The machine refused this request.", errorCode: errorCode ?? SandboxApiCodes.invalidRequest)
        default:
            return SandboxApiFailure(status: 503, message: message ?? "The machine could not be reached; try again.", errorCode: SandboxApiCodes.machineUnreachable)
        }
    }

    public static let helperUnreachable = SandboxApiFailure(status: 503, message: "The machine could not be reached; try again.", errorCode: SandboxApiCodes.machineUnreachable)

    /// A sandbox that cannot be paused or resumed on its machine (its engine says so).
    public static let notPausable = SandboxApiFailure(status: 409, message: "This sandbox cannot be paused on its machine.", errorCode: SandboxApiCodes.notPausable)
}
