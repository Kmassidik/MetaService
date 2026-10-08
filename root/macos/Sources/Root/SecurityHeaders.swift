import Hummingbird
import HTTPTypes

/// Headers every response carries. The API answers JSON only, so its policy allows nothing to load.
struct SecurityHeadersMiddleware: RouterMiddleware {
    static let contractVersion = "1.0.0"

    func handle(_ request: Request, context: RootContext, next: (Request, RootContext) async throws -> Response) async throws -> Response {
        var response = try await next(request, context)
        response.headers[.cacheControl] = "no-store"
        response.headers[.xContentTypeOptions] = "nosniff"
        response.headers[HTTPField.Name("Referrer-Policy")!] = "no-referrer"
        response.headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'none'; frame-ancestors 'none'"
        response.headers[HTTPField.Name("X-MetaService-Contract")!] = Self.contractVersion
        return response
    }
}

extension HTTPField.Name {
    static let xContentTypeOptions = HTTPField.Name("X-Content-Type-Options")!
}
