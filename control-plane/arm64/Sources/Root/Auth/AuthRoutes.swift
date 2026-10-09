import Foundation
import Hummingbird
import HTTPTypes
import RootCore
import RootStore

/// The operator account, as in the MAAS panel: the first visit creates the admin login, after that a username and password sign in.
/// Passwords are only ever compared as salted PBKDF2 hashes, and too many wrong tries from one address lock it out for a while.
struct AuthRoutes {
    let services: Services
    let guards: Guards

    static let attemptsBeforeLockout = 10
    static let lockoutSeconds: TimeInterval = 300
    static let setupPerMinute = 10
    private static let usernamePattern = #/^[A-Za-z0-9._-]{3,32}$/#
    /// A real hash to compare against when the username is wrong, so a wrong name and a wrong password take the same time.
    private static let decoySalt = Data(repeating: 7, count: PasswordHash.saltBytes)

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/auth/status", use: status)
        group.post("/api/auth/setup", use: setup)
        group.post("/api/auth/login", use: login)
        group.post("/api/auth/logout", use: logout)
    }

    /// What the panel needs before anyone is signed in: is there an account yet, and is this browser signed in.
    func status(_ request: Request, context: RootContext) async throws -> Response {
        try guards.requireHost(request)
        let signedIn = (try? guards.operatorRead(request)) != nil
        return try Json.response(Status(configured: services.admin.isConfigured, signedIn: signedIn, setupTokenRequired: services.setupGate.isOpen))
    }

    func setup(_ request: Request, context: RootContext) async throws -> Response {
        try guards.requireHost(request)
        try requireOrigin(request)
        try guards.limit("setup", per: context, max: Self.setupPerMinute, seconds: 60)
        let lockKey = "setup-token:\(context.remoteIP)"
        guard !services.throttle.isFull(lockKey, limit: Self.attemptsBeforeLockout) else { throw ApiFailure.tooMany }
        let body = try Credentials(body: try await guards.body(request), needsConfirm: true)
        guard !services.admin.isConfigured else { throw ApiFailure(status: .conflict, code: "already_set_up", message: "the admin login already exists") }
        guard services.setupGate.accepts(body.setupToken ?? "") else {
            _ = services.throttle.allow(lockKey, limit: Self.attemptsBeforeLockout, seconds: Self.lockoutSeconds)
            try services.audit.record(actor: "unknown", action: "auth.setup_denied", detail: ["from": context.remoteIP], at: services.clock.now)
            throw ApiFailure.forbidden("setup is locked: ask the operator for the setup token")
        }
        guard try services.admin.create(username: body.username, password: body.password) else {
            throw ApiFailure(status: .conflict, code: "already_set_up", message: "the admin login already exists")
        }
        services.setupGate.close()
        try services.audit.record(actor: body.username, action: "auth.setup", at: services.clock.now)
        return try signIn(username: body.username, status: .created)
    }

    func login(_ request: Request, context: RootContext) async throws -> Response {
        try guards.requireHost(request)
        try requireOrigin(request)
        let lockKey = "login:\(context.remoteIP)"
        guard !services.throttle.isFull(lockKey, limit: Self.attemptsBeforeLockout) else { throw ApiFailure.tooMany }
        let body = try Credentials(body: try await guards.body(request), needsConfirm: false)
        guard try verified(body) else {
            _ = services.throttle.allow(lockKey, limit: Self.attemptsBeforeLockout, seconds: Self.lockoutSeconds)
            try services.audit.record(actor: "unknown", action: "auth.login_denied", detail: ["from": context.remoteIP], at: services.clock.now)
            throw ApiFailure.unauthorized("wrong username or password")
        }
        try services.audit.record(actor: body.username, action: "auth.login", at: services.clock.now)
        return try signIn(username: body.username, status: .ok)
    }

    func logout(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        if let token = Cookies.value(named: services.config.sessionCookieName, header: request.headers[.cookie]) {
            try services.sessions.delete(token: token)
        }
        try services.audit.record(actor: caller.name, action: "auth.logout", at: services.clock.now)
        var response = Response(status: .noContent)
        response.headers.append(HTTPField(name: .setCookie, value: sessionCookie(value: "", maxAge: 0)))
        return response
    }

    // MARK: shared

    private func verified(_ body: Credentials) throws -> Bool {
        guard let admin = try services.admin.get() else {
            _ = PasswordHash.matches(password: body.password, salt: Self.decoySalt, iterations: PasswordHash.iterations, expected: Data(count: 32))
            return false
        }
        let passwordRight = PasswordHash.matches(password: body.password, salt: admin.salt, iterations: admin.iterations, expected: admin.hash)
        return passwordRight && Tokens.constantTimeEqual(body.username, admin.username)
    }

    private func signIn(username: String, status: HTTPResponse.Status) throws -> Response {
        let made = try services.sessions.create(username: username, now: services.clock.now)
        var response = try Json.response(Reply(username: username, csrfToken: made.csrf), status: status)
        response.headers.append(HTTPField(name: .setCookie, value: sessionCookie(value: made.token, maxAge: Int(SessionStore.lifetime))))
        return response
    }

    /// The sign-in and setup forms are posted by the panel itself, so a request from another site is refused before any password is looked at.
    private func requireOrigin(_ request: Request) throws {
        guard Origin.matches(header: request.headers[.origin], expected: services.config.publicBaseURL) else { throw ApiFailure.forbidden("request origin not allowed") }
    }

    private func sessionCookie(value: String, maxAge: Int) -> String {
        Cookies.set(name: services.config.sessionCookieName, value: value, maxAge: maxAge, secure: services.config.cookiesAreSecure, sameSite: "Strict")
    }

    private struct Status: Encodable {
        let configured: Bool
        let signedIn: Bool
        let setupTokenRequired: Bool
    }

    private struct Reply: Encodable {
        let username: String
        let csrfToken: String
    }

    private struct Credentials {
        let username: String
        let password: String
        let setupToken: String?

        init(body: Data, needsConfirm: Bool) throws {
            let object = try StrictObject(data: body, allowed: needsConfirm ? ["username", "password", "confirm", "setup_token"] : ["username", "password"])
            setupToken = needsConfirm ? try object.string("setup_token", maxLength: 200, minLength: 1) : nil
            username = try object.string("username", pattern: AuthRoutes.usernamePattern, maxLength: 32, minLength: 3)
            password = try object.string("password", maxLength: PasswordHash.maxLength, minLength: needsConfirm ? PasswordHash.minLength : 1)
            if needsConfirm {
                let again = try object.string("confirm", maxLength: PasswordHash.maxLength)
                guard again == password else { throw InputError("the two passwords are different") }
            }
        }
    }
}
