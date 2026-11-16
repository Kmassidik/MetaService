import Foundation
import HTTPTypes
import Hummingbird
import MSCore
import RootCore
import RootStore

/// The helper build a computer downloads when the panel says "Update helper" and the computer has no SSH login (it joined through Share a PC). Only an enrolled machine, with its own
/// machine token, and only the build for its own system: a machine cannot fetch another system's program.
struct HelperBuildRoutes {
    let services: Services
    let guards: Guards

    func registerAgent(on group: RouterGroup<RootContext>) {
        group.get("/v1/agents/build", use: download)
    }

    private func download(_ request: Request, context: RootContext) async throws -> Response {
        let id = try guards.machine(request, context: context)
        let machine: MachineSummary
        do { machine = try services.machines.get(id: id, now: services.clock.now) } catch MachineError.notFound { throw ApiFailure.notFound }
        guard let offer = services.helperUpdates.offer(for: machine), let data = FileManager.default.contents(atPath: offer.path) else { throw ApiFailure.notFound }
        var headers = HTTPFields()
        headers[.contentType] = "application/octet-stream"
        headers[HTTPField.Name("X-Helper-Build")!] = offer.build
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }
}
