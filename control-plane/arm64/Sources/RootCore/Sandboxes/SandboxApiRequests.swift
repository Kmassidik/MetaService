import Foundation

/// `GET /v2/sandboxes`'s query, read without trusting anything.
public struct SandboxListQuery: Equatable, Sendable {
    /// Which states to list. Nil means both (running and paused).
    public let states: Set<SandboxState>?
    public let limit: Int

    public init(states: Set<SandboxState>?, limit: Int) {
        self.states = states
        self.limit = limit
    }
}

public enum SandboxApiListQuery {
    public static let defaultLimit = 100
    public static let limitRange = 1...100
    /// The names `api.yaml` accepts in `state`.
    public static let runningName = "running"
    public static let pausedName = "paused"
    /// Every other parameter `api.yaml` lists. They are refused rather than ignored, because a filter that is ignored answers
    /// with sandboxes the program did not ask for.
    private static let unsupportedParameters: Set<String> = ["metadata", "startedAfter", "template", "order", "nextToken"]
    private static let parameters: Set<String> = unsupportedParameters.union(["state", "limit"])

    /// The filter, or a refusal. `query` is the request's parameters as they came.
    public static func parse(_ query: [String: String]) throws -> SandboxListQuery {
        if let unknown = query.keys.first(where: { !parameters.contains($0) }) {
            throw SandboxApiFailure.invalid("Unknown parameter \(unknown).")
        }
        if let unsupported = query.keys.first(where: { unsupportedParameters.contains($0) }) {
            throw SandboxApiFailure.unsupported("\(unsupported) is not supported yet; list is filtered by state and limited by limit only.")
        }
        return SandboxListQuery(states: try states(query["state"]), limit: try limit(query["limit"]))
    }

    private static func states(_ text: String?) throws -> Set<SandboxState>? {
        guard let text else { return nil }
        var states: Set<SandboxState> = []
        for name in text.split(separator: ",") {
            switch name.trimmingCharacters(in: .whitespaces) {
            case runningName: states.formUnion(SandboxState.allCases.filter(\.holdsCompute))
            case pausedName: states.insert(.paused)
            default: throw SandboxApiFailure.invalid("state must be \(runningName) or \(pausedName).")
            }
        }
        return states.isEmpty ? nil : states
    }

    private static func limit(_ text: String?) throws -> Int {
        guard let text else { return defaultLimit }
        guard let value = Int(text), limitRange.contains(value) else {
            throw SandboxApiFailure.invalid("limit must be a whole number from \(limitRange.lowerBound) to \(limitRange.upperBound).")
        }
        return value
    }
}

/// `POST /sandboxes/{sandboxID}/timeout`. Zero ends the sandbox now, which is why it is not passed to `SandboxEndTime`
/// (that one refuses a timeout of zero: "a sandbox must run at least one second").
public struct SandboxApiTimeoutBody: Equatable, Sendable {
    public let timeoutSeconds: Int

    public init(timeoutSeconds: Int) {
        self.timeoutSeconds = timeoutSeconds
    }

    public static func parse(_ body: Data) throws -> SandboxApiTimeoutBody {
        guard let json = try? JSONSerialization.jsonObject(with: body), let object = json as? [String: Any] else {
            throw SandboxApiFailure.invalid("The body must be a JSON object with a timeout.")
        }
        guard object.keys.allSatisfy({ $0 == "timeout" }) else { throw SandboxApiFailure.invalid("The body holds timeout only.") }
        guard let number = object["timeout"] as? NSNumber, number.doubleValue == number.doubleValue.rounded(),
              let timeout = Int(exactly: number), timeout >= 0 else {
            throw SandboxApiFailure.invalid("timeout must be a whole number of seconds, zero or more.")
        }
        return SandboxApiTimeoutBody(timeoutSeconds: timeout)
    }
}

/// `POST /v2/sandboxes/{sandboxID}/connect`. Absent timeout means 300 (E2B's own default).
public struct SandboxApiConnectBody: Equatable, Sendable {
    public let timeoutSeconds: Int

    public init(timeoutSeconds: Int) {
        self.timeoutSeconds = timeoutSeconds
    }

    public static func parse(_ body: Data) throws -> SandboxApiConnectBody {
        guard !body.isEmpty else { return SandboxApiConnectBody(timeoutSeconds: SandboxEndTime.defaultTimeoutSeconds) }
        guard let json = try? JSONSerialization.jsonObject(with: body), let object = json as? [String: Any] else {
            throw SandboxApiFailure.invalid("The body must be a JSON object.")
        }
        guard object.keys.allSatisfy({ ["timeout", "memory"].contains($0) }) else {
            throw SandboxApiFailure.invalid("The body holds timeout and memory only.")
        }
        if let memory = object["memory"], (memory as? NSNumber)?.boolValue == false {
            throw SandboxApiFailure.unsupported("memory false (a reboot instead of a resume) is not supported yet.")
        }
        guard let raw = object["timeout"], !(raw is NSNull) else {
            return SandboxApiConnectBody(timeoutSeconds: SandboxEndTime.defaultTimeoutSeconds)
        }
        guard let number = raw as? NSNumber, number.doubleValue == number.doubleValue.rounded(),
              let timeout = Int(exactly: number), timeout >= SandboxEndTime.minimumTimeoutSeconds else {
            throw SandboxApiFailure.invalid("timeout must be a whole number of seconds, at least \(SandboxEndTime.minimumTimeoutSeconds).")
        }
        return SandboxApiConnectBody(timeoutSeconds: timeout)
    }
}

/// The state names the public API uses, from the parent's own richer state.
public enum SandboxApiState {
    public static func name(for state: SandboxState) -> String {
        state.holdsCompute ? SandboxApiListQuery.runningName : SandboxApiListQuery.pausedName
    }
}
