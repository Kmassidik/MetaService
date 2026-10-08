import Foundation
import Hummingbird
import HTTPTypes
import RootCore
import RootStore

/// Operator sign-in with Google, plus logout. A build with FAKE_AUTH adds a test-only door; release builds never do.
struct AuthRoutes {
    let services: Services
    let guards: Guards

    static let loginPerMinute = 30
    static let oauthCookieSeconds = 600
    private static let loggedEmailLimit = 100

    func register(on group: RouterGroup<RootContext>) {
        group.get("/auth/status", use: status)
        group.get("/auth/login", use: login)
        group.get("/auth/callback", use: callback)
        group.post("/auth/logout", use: logout)
        #if FAKE_AUTH
        group.post("/auth/fake", use: fakeSignIn)
        #endif
    }

    /// Public and harmless: lets the sign-in page say whether Google sign-in is set up.
    func status(_ request: Request, context: RootContext) async throws -> Response {
        try Json.response(["google": services.config.googleConfigured])
    }

    func login(_ request: Request, context: RootContext) async throws -> Response {
        try guards.limit("login", per: context, max: Self.loginPerMinute, seconds: 60)
        let started: (location: String, browserToken: String)
        do {
            started = try services.google.start()
        } catch SignInFailure.notConfigured {
            throw ApiFailure(status: .serviceUnavailable, code: "sign_in_unavailable", message: "Google sign-in is not configured on this Root yet")
        }
        let config = services.config
        var response = redirect(to: started.location)
        response.headers.append(HTTPField(name: .setCookie, value: Cookies.set(name: config.oauthCookieName, value: started.browserToken,
                                                                                 maxAge: Self.oauthCookieSeconds, secure: config.cookiesAreSecure, sameSite: "Lax")))
        return response
    }

    func callback(_ request: Request, context: RootContext) async throws -> Response {
        try guards.limit("callback", per: context, max: Self.loginPerMinute, seconds: 60)
        let query = request.uri.queryParameters
        let identity: GoogleIdentity
        do {
            identity = try await services.google.finish(
                browserToken: Cookies.value(named: services.config.oauthCookieName, header: request.headers[.cookie]),
                states: query.getAll("state"), codes: query.getAll("code"), providerError: query.get("error") != nil)
        } catch let failure as SignInFailure {
            throw Self.apiFailure(for: failure)
        }
        return try signIn(email: identity.email, clearOauthCookie: true)
    }

    func logout(_ request: Request, context: RootContext) async throws -> Response {
        let session = try guards.operatorWrite(request)
        if let token = Cookies.value(named: services.config.sessionCookieName, header: request.headers[.cookie]) {
            try services.sessions.delete(token: token)
        }
        try services.audit.record(actor: session.email, action: "auth.logout", at: services.clock.now)
        var response = Response(status: .noContent)
        response.headers.append(HTTPField(name: .setCookie, value: sessionCookie(value: "", maxAge: 0)))
        return response
    }

    #if FAKE_AUTH
    /// Test builds only: sign in as an allow-listed email without Google. The same allow-list applies.
    func fakeSignIn(_ request: Request, context: RootContext) async throws -> Response {
        let object = try StrictObject(data: try await guards.body(request), allowed: ["email"])
        return try signIn(email: try object.string("email", maxLength: 254, minLength: 3).lowercased(), clearOauthCookie: false)
    }
    #endif

    // MARK: shared

    private func signIn(email: String, clearOauthCookie: Bool) throws -> Response {
        let now = services.clock.now
        guard services.config.allowedEmails.contains(email) else {
            try services.audit.record(actor: "unknown", action: "auth.login_denied", detail: ["email": String(email.prefix(Self.loggedEmailLimit))], at: now)
            throw ApiFailure.forbidden("this account is not allowed")
        }
        let made = try services.sessions.create(email: email, now: now)
        try services.audit.record(actor: email, action: "auth.login", at: now)
        var response = redirect(to: "/")
        response.headers.append(HTTPField(name: .setCookie, value: sessionCookie(value: made.token, maxAge: Int(SessionStore.lifetime))))
        if clearOauthCookie {
            response.headers.append(HTTPField(name: .setCookie, value: Cookies.set(name: services.config.oauthCookieName, value: "", maxAge: 0,
                                                                                    secure: services.config.cookiesAreSecure, sameSite: "Lax")))
        }
        return response
    }

    private func sessionCookie(value: String, maxAge: Int) -> String {
        Cookies.set(name: services.config.sessionCookieName, value: value, maxAge: maxAge, secure: services.config.cookiesAreSecure, sameSite: "Strict")
    }

    private func redirect(to location: String) -> Response {
        Response(status: .found, headers: [.location: location])
    }

    private static func apiFailure(for failure: SignInFailure) -> ApiFailure {
        switch failure {
        case .notConfigured: return ApiFailure(status: .serviceUnavailable, code: "sign_in_unavailable", message: "Google sign-in is not configured on this Root yet")
        case .expired: return ApiFailure(status: .badRequest, code: "sign_in_expired", message: "sign-in expired, start again")
        case .denied: return ApiFailure.forbidden("Google sign-in was cancelled or the email is not verified")
        case .provider: return ApiFailure(status: .badGateway, code: "sign_in_failed", message: "Google sign-in failed")
        }
    }
}
