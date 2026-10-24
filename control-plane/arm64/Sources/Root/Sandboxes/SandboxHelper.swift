import Foundation
import RootCore

/// A helper's answer about one sandbox: the part the parent needs. The rest of the helper's `Sandbox` is the helper's own
/// business.
struct HelperSandbox: Equatable {
    let state: SandboxState
    /// The in-guest daemon's version, as the helper reported it (nil when it did not say).
    let daemonVersion: String?
}

/// What a helper call failed with. The service turns these into the API's own answers, so a helper that is down is a 503 and
/// never a 500 storm.
enum SandboxHelperError: Error, Equatable {
    case unreachable
    /// The helper answered with its own refusal (status, error code, message).
    case refused(status: Int, code: String?, message: String?)
}

/// Everything the sandbox API asks of a helper, so the service can be driven by a fake one in tests.
protocol SandboxHelperCalling: Sendable {
    func create(machine: String, command: SandboxHelperCreate) async throws -> HelperSandbox
    func sandbox(machine: String, id: String) async throws -> HelperSandbox
    func delete(machine: String, id: String) async throws
    func setEnd(machine: String, id: String, endAt: Date) async throws
    func resume(machine: String, id: String) async throws -> HelperSandbox
    func pause(machine: String, id: String) async throws -> HelperSandbox
    /// The helper's readings for one sandbox, passed through as the helper sent them (the API's `SandboxMetric` shape).
    func metrics(machine: String, id: String, from: Int?, until: Int?) async throws -> [[String: Any]]
}

/// One create, as `contract/openapi.yaml`'s `SandboxCreate` wants it.
struct SandboxHelperCreate: Equatable {
    let id: String
    let template: String
    let shape: SandboxShape
    let endAt: Date
    let envVars: [String: String]
    /// Secret: it goes to the helper and is never logged.
    let accessToken: String
}

/// The parent's end of the helper's sandbox routes, over the same tunnel and command token as every other parent→helper call.
struct AgentSandboxHelper: SandboxHelperCalling {
    static let createSeconds: TimeInterval = 30
    static let changeSeconds: TimeInterval = 15
    /// The helper's "no such sandbox" and "already gone" are the same to a delete.
    static let notFound = 404
    static let notPausable = 409
    private static let plainTimeFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

    let client: AgentClient

    func create(machine: String, command: SandboxHelperCreate) async throws -> HelperSandbox {
        let body: [String: Any] = [
            "id": command.id, "template": command.template,
            "vcpu": command.shape.vcpu, "ram_mb": command.shape.ramMb, "disk_mb": command.shape.diskMb,
            "end_at": Self.plainTime(command.endAt), "on_end": "kill", "internet": false,
            "env_vars": command.envVars, "access_token": command.accessToken,
        ]
        return try await call(machine: machine, method: "POST", path: "/v1/sandboxes", body: body, timeout: Self.createSeconds)
    }

    func sandbox(machine: String, id: String) async throws -> HelperSandbox {
        try await call(machine: machine, method: "GET", path: Self.path(id))
    }

    func delete(machine: String, id: String) async throws {
        let reply = try await raw(machine: machine, method: "DELETE", path: Self.path(id), body: nil)
        guard reply.status != Self.notFound else { return }
        try Self.require(reply)
    }

    func setEnd(machine: String, id: String, endAt: Date) async throws {
        let body: [String: Any] = ["end_at": Self.plainTime(endAt), "on_end": "kill"]
        try Self.require(try await raw(machine: machine, method: "PUT", path: Self.path(id) + "/end", body: body))
    }

    /// A sandbox that is running comes back as it is; a paused one is resumed.
    func resume(machine: String, id: String) async throws -> HelperSandbox {
        try await call(machine: machine, method: "PUT", path: Self.path(id) + "/resume")
    }

    /// Saves the sandbox and stops it; the helper answers 409 when it is already paused, which the parent turns into the API's 409.
    func pause(machine: String, id: String) async throws -> HelperSandbox {
        try await call(machine: machine, method: "PUT", path: Self.path(id) + "/pause")
    }

    /// The helper's own readings, forwarded unchanged. The shape is the helper's `SandboxMetric` list, so the parent validates
    /// only that the answer is a list of objects and never rewrites a reading.
    func metrics(machine: String, id: String, from: Int?, until: Int?) async throws -> [[String: Any]] {
        var query: [String] = []
        if let from { query.append("start=\(from)") }
        if let until { query.append("end=\(until)") }
        let path = Self.path(id) + "/metrics" + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
        let reply = try await raw(machine: machine, method: "GET", path: path, body: nil)
        try Self.require(reply)
        guard let list = reply.json as? [[String: Any]] else {
            throw SandboxHelperError.refused(status: 502, code: "bad_reply", message: "the machine's answer was not a list of readings")
        }
        return list
    }

    // MARK: the wire

    private func call(machine: String, method: String, path: String, body: [String: Any]? = nil,
                      timeout: TimeInterval = changeSeconds) async throws -> HelperSandbox {
        let reply = try await raw(machine: machine, method: method, path: path, body: body, timeout: timeout)
        try Self.require(reply)
        return try Self.sandbox(from: reply.json)
    }

    private func raw(machine: String, method: String, path: String, body: [String: Any]?,
                     timeout: TimeInterval = changeSeconds) async throws -> AgentReply {
        do {
            return try await client.call(machine: machine, method: method, path: path, body: body, timeout: timeout)
        } catch {
            throw SandboxHelperError.unreachable
        }
    }

    private static func path(_ id: String) -> String { "/v1/sandboxes/\(id)" }

    private static func require(_ reply: AgentReply) throws {
        guard (200..<300).contains(reply.status) else {
            let error = reply.json?["error"] as? [String: Any]
            throw SandboxHelperError.refused(status: reply.status, code: error?["code"] as? String, message: error?["message"] as? String)
        }
    }

    private static func sandbox(from json: [String: Any]?) throws -> HelperSandbox {
        guard let raw = json?["state"] as? String, let state = SandboxState(rawValue: raw) else {
            throw SandboxHelperError.refused(status: 502, code: "bad_reply", message: "the machine's answer had no sandbox state")
        }
        return HelperSandbox(state: state, daemonVersion: json?["daemon_version"] as? String)
    }

    /// `contract/openapi.yaml`'s `SandboxTime`: UTC, seconds, `2026-10-24T09:30:00Z`.
    static func plainTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = plainTimeFormat
        return formatter.string(from: date)
    }
}
