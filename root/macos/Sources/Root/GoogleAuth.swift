import Foundation
import RootCore

struct GoogleIdentity: Equatable {
    let subject: String
    let email: String
}

enum SignInFailure: Error {
    case notConfigured
    case expired
    case denied
    case provider
}

/// Google sign-in by authorization code with PKCE, state and nonce. The ID token must come with a verified email.
final class GoogleAuth: @unchecked Sendable {
    private struct Attempt {
        let state: String
        let verifier: String
        let nonce: String
        let expires: Date
    }

    private let config: RootConfig
    private let clock: Clock
    private let lock = NSLock()
    private var attempts: [String: Attempt] = [:]
    private let session: URLSession
    private static let attemptLifetime: TimeInterval = 600
    private static let maxAttempts = 1024
    private static let maxReplyBytes = 128 * 1024
    private static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let verifyURL = "https://oauth2.googleapis.com/tokeninfo"

    init(config: RootConfig, clock: Clock) {
        self.config = config
        self.clock = clock
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 20
        options.httpCookieStorage = nil
        options.urlCache = nil
        session = URLSession(configuration: options, delegate: NoRedirect(), delegateQueue: nil)
    }

    // MARK: step 1, send the browser to Google

    func start() throws -> (location: String, browserToken: String) {
        guard config.googleConfigured else { throw SignInFailure.notConfigured }
        let browser = Tokens.random(), attempt = Attempt(state: Tokens.random(), verifier: Tokens.random(), nonce: Tokens.random(),
                                                         expires: clock.now.addingTimeInterval(Self.attemptLifetime))
        remember(attempt, for: browser)
        var url = URLComponents(string: Self.authURL)!
        url.queryItems = [
            ("client_id", config.googleClientId ?? ""), ("redirect_uri", config.callbackURL), ("response_type", "code"),
            ("scope", "openid email"), ("state", attempt.state), ("nonce", attempt.nonce),
            ("code_challenge", Pkce.challenge(for: attempt.verifier)), ("code_challenge_method", "S256"), ("prompt", "select_account"),
        ].map { URLQueryItem(name: $0.0, value: $0.1) }
        return (url.url!.absoluteString, browser)
    }

    private func remember(_ attempt: Attempt, for browser: String) {
        lock.lock(); defer { lock.unlock() }
        let now = clock.now
        attempts = attempts.filter { $0.value.expires > now }
        if attempts.count >= Self.maxAttempts, let oldest = attempts.min(by: { $0.value.expires < $1.value.expires })?.key { attempts[oldest] = nil }
        attempts[Tokens.sha256Hex(browser)] = attempt
    }

    private func take(browser: String) -> Attempt? {
        lock.lock(); defer { lock.unlock() }
        guard let found = attempts.removeValue(forKey: Tokens.sha256Hex(browser)), found.expires > clock.now else { return nil }
        return found
    }

    // MARK: step 2, Google sent the browser back

    func finish(browserToken: String?, states: [String], codes: [String], providerError: Bool) async throws -> GoogleIdentity {
        guard config.googleConfigured else { throw SignInFailure.notConfigured }
        guard let browserToken, let attempt = take(browser: browserToken) else { throw SignInFailure.expired }
        guard states.count == 1, Tokens.constantTimeEqual(states[0], attempt.state) else { throw SignInFailure.expired }
        guard !providerError else { throw SignInFailure.denied }
        guard codes.count == 1, !codes[0].isEmpty, codes[0].count <= 4096 else { throw SignInFailure.provider }
        let idToken = try await exchange(code: codes[0], verifier: attempt.verifier)
        let verified = try await json(URLRequest(url: tokenInfoURL(idToken)))
        return try identity(idToken: idToken, verified: verified, nonce: attempt.nonce)
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [("grant_type", "authorization_code"), ("code", code), ("client_id", config.googleClientId ?? ""),
                           ("client_secret", config.googleClientSecret ?? ""), ("redirect_uri", config.callbackURL), ("code_verifier", verifier)]
            .map { URLQueryItem(name: $0.0, value: $0.1) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let reply = try await json(request)
        guard let token = reply["id_token"] as? String, (reply["token_type"] as? String)?.lowercased() == "bearer" else { throw SignInFailure.provider }
        return token
    }

    private func tokenInfoURL(_ idToken: String) -> URL {
        var parts = URLComponents(string: Self.verifyURL)!
        parts.queryItems = [URLQueryItem(name: "id_token", value: idToken)]
        return parts.url!
    }

    private func json(_ request: URLRequest) async throws -> [String: Any] {
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse,
              http.statusCode == 200, data.count <= Self.maxReplyBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SignInFailure.provider }
        return object
    }

    // MARK: checking who signed in

    private func identity(idToken: String, verified: [String: Any], nonce: String) throws -> GoogleIdentity {
        do {
            let claims = try IdTokenClaims.decode(idToken)
            let found = try IdTokenClaims.identity(claims: claims, verified: verified, clientId: config.googleClientId ?? "", nonce: nonce, now: clock.now)
            return GoogleIdentity(subject: found.subject, email: found.email)
        } catch ClaimsFailure.emailNotVerified {
            throw SignInFailure.denied
        } catch {
            throw SignInFailure.provider
        }
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
