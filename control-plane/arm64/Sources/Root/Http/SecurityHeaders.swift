import Hummingbird
import HTTPTypes
import MSCore

/// Headers every response carries. The API answers JSON only, so its policy allows nothing to load.
struct SecurityHeadersMiddleware: RouterMiddleware {
    /// Over https the browser is told to use only https for this site for a year, so a downgrade to plain http is refused.
    var hsts = false
    static let strictTransport = HTTPField.Name("Strict-Transport-Security")!
    static let hstsValue = "max-age=31536000"
    static let contractVersion = ContractVersion.current
    static let csp = HTTPField.Name("Content-Security-Policy")!
    static let apiPolicy = "default-src 'none'; frame-ancestors 'none'"

    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        if response.headers[.cacheControl] == nil { response.headers[.cacheControl] = "no-store" }
        response.headers[.xContentTypeOptions] = "nosniff"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        if hsts { response.headers[Self.strictTransport] = Self.hstsValue }
        if response.headers[Self.csp] == nil { response.headers[Self.csp] = Self.apiPolicy }
        response.headers[HTTPField.Name("X-MetaService-Contract")!] = Self.contractVersion
        return response
    }
}

extension HTTPField.Name {
    static let xContentTypeOptions = HTTPField.Name("X-Content-Type-Options")!
}
