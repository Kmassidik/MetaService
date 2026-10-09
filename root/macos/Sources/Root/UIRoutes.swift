import Foundation
import Hummingbird
import NIOCore
import RootCore

/// Serves the built panel UI (ui/dist). Only GET, only files inside the UI folder, with a strict page policy.
struct UIRoutes {
    let directory: URL

    static let pagePolicy = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
        + "font-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
    static let assetCache = "public, max-age=31536000, immutable"

    init(directory: String) {
        self.directory = URL(fileURLWithPath: directory).resolvingSymlinksInPath()
    }

    func register(on group: RouterGroup<RootContext>) {
        group.get("/", use: serve)
        group.get("/assets/{path+}", use: serve)
        group.get("/fonts/{path+}", use: serve)
        group.get("/favicon.svg", use: serve)
    }

    func serve(_ request: Request, context: RootContext) async throws -> Response {
        guard let file = StaticPath.clean(request.uri.path), let type = StaticPath.contentType(for: file) else { throw ApiFailure.notFound }
        let url = directory.appendingPathComponent(file).resolvingSymlinksInPath()
        guard url.path.hasPrefix(directory.path + "/"), let data = FileManager.default.contents(atPath: url.path) else { throw ApiFailure.notFound }
        var headers = HTTPFields()
        headers[.contentType] = type
        headers[.cacheControl] = StaticPath.isHashedAsset(file) ? Self.assetCache : "no-cache"
        headers[SecurityHeadersMiddleware.csp] = Self.pagePolicy
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}
