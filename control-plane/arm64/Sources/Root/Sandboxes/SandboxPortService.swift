import Foundation
import RootCore
import RootStore

/// One request on a port host, as the route received it. The token has already been picked out of `?token=` or
/// `X-Port-Token`, so the service never reads headers to find it.
struct SandboxPortIncoming {
    let host: String?
    let method: String
    let path: String
    let query: String?
    let token: String?
    let headers: [(name: String, value: String)]
    let body: Data
}

/// An expose: what the program fetches, and whether this call made the record.
struct SandboxPortExposed {
    let port: SandboxApiPort
    let created: Bool
}

/// Exposing a sandbox's port and forwarding to it (see `sandbox/README.md`, "Addresses"). The order matters: the label is
/// known before any work, and the token is checked before the machine is called, so a request without a good token never
/// reaches a helper.
struct SandboxPortService {
    /// The code for something that is the parent's own fault, never the caller's.
    static let internalCode = "internal"

    let services: Services
    let forwarder: SandboxPortForwarding

    // MARK: exposing

    func expose(team: String, id: String, port: Int) throws -> SandboxPortExposed {
        let now = services.clock.now
        let record = try own(team: team, id: id)
        guard Self.servesPorts(record.state) else { throw Self.notRunning(record.state) }
        let label = try label(sandbox: record.id, port: port)
        let stored: (record: SandboxPortRecord, created: Bool)
        do {
            stored = try services.sandboxPorts.expose(sandbox: record.id, port: port, label: label, now: now)
        } catch SandboxPortStoreError.labelTaken {
            // A derived 80-bit label collided with another port's. Nothing a caller can fix, and nothing to retry.
            throw SandboxApiFailure(status: 500, message: "This address could not be made; try another port.", errorCode: Self.internalCode)
        }
        let token = try token(label: stored.record.label, sandbox: record.id, port: port, now: now)
        let host = PortHosts.host(label: stored.record.label, domain: services.config.sandboxDomain)
        return SandboxPortExposed(port: SandboxApiPort(host: host, token: token.token, expiresAt: Self.iso(token.expiresAt)),
                                  created: stored.created)
    }

    // MARK: forwarding

    func forward(_ incoming: SandboxPortIncoming) async throws -> SandboxPortReply {
        guard let label = PortHosts.label(inHost: incoming.host, domain: services.config.sandboxDomain) else {
            throw SandboxApiFailure.portNotFound
        }
        guard let stored = try services.sandboxPorts.find(label: label) else { throw SandboxApiFailure.portNotFound }
        let claims = try claims(for: incoming.token, label: label, stored: stored)
        guard let record = try services.sandboxes.get(id: claims.sandbox), Self.servesPorts(record.state) else {
            throw SandboxApiFailure.portNotRunning
        }
        let call = SandboxPortCall(machine: record.machine, sandbox: stored.sandbox, port: stored.port, method: incoming.method,
                                   path: incoming.path, query: incoming.query, headers: incoming.headers, body: incoming.body)
        do {
            return try await forwarder.forward(call)
        } catch {
            throw SandboxApiFailure.portUnreachable
        }
    }

    // MARK: pieces

    /// The record, when it is this team's. Unknown and another team's are the same 404, as everywhere in the public API. An
    /// ended sandbox is still this team's, on purpose: exposing a port on it is a 409 ("it has ended"), not a 404 that would send
    /// a program looking for a sandbox it already knows.
    private func own(team: String, id: String) throws -> SandboxRecord {
        guard let record = try services.sandboxes.get(id: id), record.team == team else { throw SandboxApiFailure.noSuchSandbox() }
        return record
    }

    /// The claims a token proves, when it was given out for this host. A missing, expired, forged or other-host token is the
    /// same 401: what the caller needs is a new host and token, and telling them which fault it was helps only an attacker.
    private func claims(for token: String?, label: String, stored: SandboxPortRecord) throws -> PortToken.Claims {
        guard let token else { throw SandboxApiFailure.portToken }
        let verified = PortToken.verify(token: token, label: label, now: services.clock.now) { subject in
            services.secrets.signature(subject, purpose: PortToken.purpose)
        }
        guard case .success(let claims) = verified, claims.sandbox == stored.sandbox, claims.port == stored.port else {
            throw SandboxApiFailure.portToken
        }
        return claims
    }

    /// The label for one port: the Root's signature over the sandbox and port, cut to 80 bits. Nil only when the signature
    /// helper itself misbehaves, which is a 500 and never a caller's fault.
    private func label(sandbox: String, port: Int) throws -> String {
        let signature = services.secrets.signature(PortHosts.subject(sandbox: sandbox, port: port), purpose: PortHosts.purpose)
        guard let label = PortHosts.label(from: signature) else {
            throw SandboxApiFailure(status: 500, message: "This address could not be made.", errorCode: Self.internalCode)
        }
        return label
    }

    private func token(label: String, sandbox: String, port: Int, now: Date) throws -> PortToken.Issued {
        let expiresAt = PortToken.expiry(now: now)
        let signature = services.secrets.signature(PortToken.subject(label: label, sandbox: sandbox, port: port, expiresAt: expiresAt),
                                                   purpose: PortToken.purpose)
        guard let issued = PortToken.issue(sandbox: sandbox, port: port, label: label, now: now, lifetimeSignature: signature) else {
            throw SandboxApiFailure(status: 500, message: "A link for this port could not be made.", errorCode: Self.internalCode)
        }
        return issued
    }

    /// A port works only while the sandbox holds compute: a paused one keeps its programs but answers nothing, and an ended one
    /// is gone. Both are a 409 on expose (the sandbox exists, just not now) and a 502 when traffic arrives, which is what E2B's
    /// SDKs read as "not running".
    private static func servesPorts(_ state: SandboxState) -> Bool {
        state.holdsCompute
    }

    /// The refusal for a sandbox that cannot serve a port now, in plain words.
    private static func notRunning(_ state: SandboxState) -> SandboxApiFailure {
        let message = state == .paused
            ? "This sandbox is paused; connect to it before opening a port."
            : "This sandbox has ended."
        return SandboxApiFailure(status: 409, message: message, errorCode: SandboxApiCodes.notRunning)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
