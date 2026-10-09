import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The AI proxy and its panel status. The provider key never leaves BrainService; bundles only ever hold a short-lived capability.
struct BrainRoutes {
    let services: Services
    let guards: Guards

    static let capabilitiesPerMinute = 30
    static let chatsPerMinute = 20
    static let testsPerMinute = 5
    private static let testPrompt = "Reply with the single word: ok"
    private static let testMaxTokens = 8

    func registerOperator(on group: RouterGroup<RootContext>) {
        group.get("/api/brain", use: status)
        group.post("/api/brain/test", use: test)
    }

    func registerAgent(on group: RouterGroup<RootContext>) {
        group.post("/v1/brain/capability", use: capability)
        group.post("/v1/brain/chat", use: chat)
    }

    /// A chat shows its own access key and gets a capability that expires soon. Wrong keys count toward the same lockout as wrong machine tokens.
    private func capability(_ request: Request, context: RootContext) async throws -> Response {
        try guards.limit("brain-capability", per: context, max: Self.capabilitiesPerMinute, seconds: 60)
        let target = try chatTarget(for: try guards.bearerOrRefuse(request, context: context), context: context)
        guard services.config.aiConfigured else { throw ApiFailure(status: .serviceUnavailable, code: "not_configured", message: "no AI provider is set up on the Root") }
        let now = services.clock.now, seconds = services.config.capabilitySeconds
        let token = Tokens.random()
        let parts = target.split(separator: "/", maxSplits: 1).map(String.init)
        try services.brain.issue(tokenHash: Tokens.sha256Hex(token), machine: parts[0], workload: parts.count > 1 ? parts[1] : nil, expiresAt: now.addingTimeInterval(Double(seconds)), now: now)
        return try Json.response(CapabilityReply(capability: token, expiresIn: seconds))
    }

    private func chat(_ request: Request, context: RootContext) async throws -> Response {
        let token = try guards.bearerOrRefuse(request, context: context)
        guard let grant = try services.brain.lookup(tokenHash: Tokens.sha256Hex(token), now: services.clock.now) else {
            _ = services.throttle.allow(Guards.badTokenKey(context), limit: Guards.badTokenLimit, seconds: Guards.badTokenWindow)
            throw ApiFailure.unauthorized("missing, wrong or expired capability")
        }
        guard services.throttle.allow("brain-chat:\(Tokens.sha256Hex(token))", limit: Self.chatsPerMinute, seconds: 60) else { throw ApiFailure.tooMany }
        let message = try ChatMessage(body: try await guards.body(request)).text
        let answer = try await ask(message, maxTokens: nil)
        try services.brain.record(machine: grant.machine, workload: grant.workload, promptTokens: answer.promptTokens, completionTokens: answer.completionTokens, now: services.clock.now)
        return try Json.response(ChatReply(reply: answer.text, usage: .init(promptTokens: answer.promptTokens, completionTokens: answer.completionTokens)))
    }

    private func status(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let config = services.config
        let host = config.aiBaseURL.flatMap { URL(string: $0)?.host }
        return try Json.response(BrainStatus(configured: config.aiConfigured, model: config.aiConfigured ? config.aiModel : nil, host: config.aiConfigured ? host : nil,
                                             maxTokens: config.aiMaxTokens, usage: try services.brain.usage()))
    }

    private func test(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        guard services.throttle.allow("brain-test", limit: Self.testsPerMinute, seconds: 60) else { throw ApiFailure.tooMany }
        let answer = try await ask(Self.testPrompt, maxTokens: Self.testMaxTokens)
        try services.brain.record(machine: "root", workload: nil, promptTokens: answer.promptTokens, completionTokens: answer.completionTokens, now: services.clock.now)
        try services.audit.record(actor: caller.name, action: "brain.test", at: services.clock.now)
        return try Json.response(["ok": true])
    }

    private func ask(_ message: String, maxTokens: Int?) async throws -> BrainAnswer {
        do {
            return try await services.brainService.ask(message, maxTokens: maxTokens)
        } catch BrainFailure.notConfigured {
            throw ApiFailure(status: .serviceUnavailable, code: "not_configured", message: "no AI provider is set up on the Root")
        } catch {
            throw ApiFailure(status: .badGateway, code: "upstream_failed", message: "the AI provider did not answer")
        }
    }

    /// Which machine or workload owns this chat key, found by comparing against every stored key in constant time. Unknown keys feed the lockout.
    private func chatTarget(for key: String, context: RootContext) throws -> String {
        var found: String?
        for entry in try services.chatAccess.all() {
            guard let stored = try? services.secrets.open(entry.sealedKey), Tokens.constantTimeEqual(stored, key) else { continue }
            found = entry.target
        }
        guard let found else {
            _ = services.throttle.allow(Guards.badTokenKey(context), limit: Guards.badTokenLimit, seconds: Guards.badTokenWindow)
            throw ApiFailure.unauthorized("missing or wrong access key")
        }
        return found
    }
}

private struct ChatMessage {
    let text: String

    init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: ["message"])
        let raw = try object.string("message", maxLength: BrainRules.maxMessageCharacters)
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InputError("message must not be empty") }
    }
}

private struct CapabilityReply: Encodable {
    let capability: String
    let expiresIn: Int
}

private struct ChatReply: Encodable {
    struct Usage: Encodable {
        let promptTokens: Int
        let completionTokens: Int
    }
    let reply: String
    let usage: Usage
}

private struct BrainStatus: Encodable {
    let configured: Bool
    let model: String?
    let host: String?
    let maxTokens: Int
    let usage: [BrainUsage]
}
