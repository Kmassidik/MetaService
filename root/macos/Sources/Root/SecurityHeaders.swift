import Hummingbird
import HTTPTypes

/// Headers every response carries. The API answers JSON only, so its policy allows nothing to load.
struct SecurityHeadersMiddleware: RouterMiddleware {
    static let contractVersion = "1.0.0"
    static let csp = HTTPField.Name("Content-Security-Policy")!
    static let apiPolicy = "default-src 'none'; frame-ancestors 'none'"

    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        if response.headers[.cacheControl] == nil { response.headers[.cacheControl] = "no-store" }
        response.headers[.xContentTypeOptions] = "nosniff"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        if response.headers[Self.csp] == nil { response.headers[Self.csp] = Self.apiPolicy }
        response.headers[HTTPField.Name("X-MetaService-Contract")!] = Self.contractVersion
        return response
    }
}

extension HTTPField.Name {
    static let xContentTypeOptions = HTTPField.Name("X-Content-Type-Options")!
}
