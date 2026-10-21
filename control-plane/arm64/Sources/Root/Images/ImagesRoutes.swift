import Foundation
import Hummingbird
import MSCore
import RootCore
import RootStore

/// What the panel reads to fill the Image choice of the Create VM form. Reads: the operator's session and the right Host, like the other reads.
struct ImagesRoutes {
    let services: Services
    let guards: Guards

    static let readsPerMinute = 120

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/images", use: catalog)
        group.get("/api/machines/{id}/images", use: forMachine)
    }

    private func catalog(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("images", per: context, max: Self.readsPerMinute, seconds: 60)
        return try Json.response(CatalogReply(images: ImageCatalog.entries))
    }

    private func forMachine(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        try guards.limit("images", per: context, max: Self.readsPerMinute, seconds: 60)
        let id = try context.machineId()
        do {
            return try Json.response(try await services.images.reply(for: id))
        } catch MachineError.notFound {
            throw ApiFailure.notFound
        }
    }
}

private struct CatalogReply: Encodable { let images: [ImageEntry] }
