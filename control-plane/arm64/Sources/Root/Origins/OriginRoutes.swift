import Foundation
import Hummingbird
import HTTPTypes
import NIOCore
import RootCore
import RootStore

/// Who created a VM, in full (mcp/SPEC.md section 10.3). The record is read with its seal checked: `intact` is false when it no longer matches what the parent sealed.
struct OriginRoutes {
    let services: Services
    let guards: Guards

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/machines/{id}/workloads/{workload}/origin", use: show)
    }

    private func show(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        guard let machine = context.parameters.get("id"), let workload = context.parameters.get("workload"), Ids.isValid(machine), Ids.isValid(workload) else { throw ApiFailure.notFound }
        let found = try services.origins.get(machine: machine, workload: workload)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        let data = try JSONSerialization.data(withJSONObject: ["origin": McpService.null(found.map(Self.view))], options: [.sortedKeys])
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    private static func iso(_ seconds: Int?) -> Any { seconds.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? NSNull() }

    private static func view(_ read: VmOriginRead) -> [String: Any] {
        let record = read.record, input = record.input
        return ["kind": input.kind.rawValue, "label": VmCreatedBy.label(of: record), "actor": input.actor, "person_name": McpService.null(input.personName),
                "token_prefix": McpService.null(input.tokenPrefix), "client": McpService.null(VmCreatedBy.clientText(input)), "source_ip": McpService.null(input.sourceIp),
                "created_at": iso(record.createdAt), "backfilled": record.backfilled, "deleted_at": iso(record.deletedAt), "deleted_by": McpService.null(record.deletedBy),
                "fingerprint": VmOriginSeal.fingerprint(of: record.seal), "intact": read.intact]
    }
}
