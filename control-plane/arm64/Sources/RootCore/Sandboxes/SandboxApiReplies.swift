import Foundation

/// The bodies the public API answers with, in the camelCase of `sandbox/api.yaml` (E2B's spilling) rather than the panel's
/// snake_case. They are built from explicit values, so a route cannot forget a required field or invent one.
public enum SandboxApiDefaults {
    /// Kept only because older SDKs read it; always the same value (see `api.yaml`).
    public static let clientID = "metaservice"
    /// The envd we ship, reported when a helper does not say its own version. The SDK turns features on by version.
    public static let envdVersion = "0.10.2"
    /// An envd version is plain X.Y.Z; anything else (empty, a git describe, a word) is not reported as one.
    public static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }
}

/// The six fields a create and a connect answer with. `envdAccessToken` is the one secret here: it goes to the program and
/// is never logged, and it is not part of get or list.
public struct SandboxApiSandbox: Encodable, Equatable {
    public let templateID: String
    public let sandboxID: String
    public let clientID: String
    public let envdVersion: String
    public let envdAccessToken: String
    public let domain: String

    public init(templateID: String, sandboxID: String, clientID: String = SandboxApiDefaults.clientID,
                envdVersion: String, envdAccessToken: String, domain: String) {
        self.templateID = templateID
        self.sandboxID = sandboxID
        self.clientID = clientID
        self.envdVersion = envdVersion
        self.envdAccessToken = envdAccessToken
        self.domain = domain
    }

    enum CodingKeys: String, CodingKey { case templateID, sandboxID, clientID, envdVersion, envdAccessToken, domain }
}

/// One sandbox as the API describes it: the record the parent keeps, plus the values that come from the template or the team.
public struct SandboxApiDetail: Encodable, Equatable {
    public let templateID: String
    public let sandboxID: String
    public let clientID: String
    public let startedAt: String
    public let endAt: String
    public let cpuCount: Int
    public let memoryMB: Int
    public let diskSizeMB: Int
    public let envdVersion: String
    public let domain: String
    public let metadata: [String: String]
    public let state: String
    public let allowInternetAccess: Bool
    public let lifecycle: SandboxApiLifecycle
    public let volumeMounts: [String]

    public init(templateID: String, sandboxID: String, startedAt: String, endAt: String, cpuCount: Int, memoryMB: Int,
                diskSizeMB: Int, envdVersion: String, domain: String, state: String,
                clientID: String = SandboxApiDefaults.clientID) {
        self.templateID = templateID
        self.sandboxID = sandboxID
        self.clientID = clientID
        self.startedAt = startedAt
        self.endAt = endAt
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskSizeMB = diskSizeMB
        self.envdVersion = envdVersion
        self.domain = domain
        self.metadata = [:]
        self.state = state
        self.allowInternetAccess = false
        self.lifecycle = SandboxApiLifecycle()
        self.volumeMounts = []
    }

    enum CodingKeys: String, CodingKey {
        case templateID, sandboxID, clientID, startedAt, endAt, cpuCount, memoryMB, diskSizeMB, envdVersion, domain,
             metadata, state, allowInternetAccess, lifecycle, volumeMounts
    }
}

/// What happens at the end time. v1 ends a sandbox and never pauses it on timeout, so both values are the only truthful ones.
public struct SandboxApiLifecycle: Encodable, Equatable {
    public let onTimeout: String
    public let autoResume: Bool

    public init(onTimeout: String = "kill", autoResume: Bool = false) {
        self.onTimeout = onTimeout
        self.autoResume = autoResume
    }
}

/// One row of `GET /v2/sandboxes`; the same as the detail, without the fields a list does not carry.
public struct SandboxApiListed: Encodable, Equatable {
    public let templateID: String
    public let sandboxID: String
    public let clientID: String
    public let startedAt: String
    public let endAt: String
    public let cpuCount: Int
    public let memoryMB: Int
    public let diskSizeMB: Int
    public let envdVersion: String
    public let metadata: [String: String]
    public let state: String

    public init(templateID: String, sandboxID: String, startedAt: String, endAt: String, cpuCount: Int, memoryMB: Int,
                diskSizeMB: Int, envdVersion: String, state: String, clientID: String = SandboxApiDefaults.clientID) {
        self.templateID = templateID
        self.sandboxID = sandboxID
        self.clientID = clientID
        self.startedAt = startedAt
        self.endAt = endAt
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskSizeMB = diskSizeMB
        self.envdVersion = envdVersion
        self.metadata = [:]
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case templateID, sandboxID, clientID, startedAt, endAt, cpuCount, memoryMB, diskSizeMB, envdVersion, metadata, state
    }
}

/// `{ code, message, error_code }`, with `code` repeating the HTTP status because the SDKs check it.
public struct SandboxApiErrorBody: Encodable, Equatable {
    public let code: Int
    public let message: String
    public let errorCode: String?

    public init(_ failure: SandboxApiFailure) {
        self.code = failure.status
        self.message = failure.message
        self.errorCode = failure.errorCode
    }

    enum CodingKeys: String, CodingKey { case code, message, errorCode = "error_code" }
}
