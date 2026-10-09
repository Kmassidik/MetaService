import Foundation
import Hummingbird
import RootCore
import RootStore

/// The panel's scan screen: set-up facts, start a run, read results, and turn chosen devices into enrollment tokens.
struct ScanRoutes {
    let services: Services
    let guards: Guards

    static let scansPerMinute = 6

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/scan/setup", use: setup)
        group.post("/api/scans", use: start)
        group.get("/api/scans/latest", use: latest)
        group.get("/api/scans/{id}", use: show)
        group.post("/api/scans/{id}/add", use: add)
    }

    func setup(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try Json.response(services.scanService.setup())
    }

    func start(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("scan", per: context, max: Self.scansPerMinute, seconds: 60)
        let id = try services.scanService.begin(actor: caller.name)
        return try Json.response(Started(id: id, state: "running"), status: .accepted)
    }

    func latest(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        return try Json.response(Latest(scan: try services.scans.latest()))
    }

    func show(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        do {
            return try Json.response(Latest(scan: try services.scans.get(id: try runId(context))))
        } catch ScanError.notFound {
            throw ApiFailure.notFound
        }
    }

    func add(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        let id = try runId(context)
        let body = try AddScanRequest(body: try await guards.body(request))
        let picked = try body.items.map { item -> (AddScanItem, ScanResultRow) in
            do { return (item, try services.scans.result(runId: id, resultId: item.resultId)) } catch ScanError.notFound { throw ApiFailure.notFound }
        }
        guard picked.allSatisfy({ $0.1.machine == nil }) else { throw ApiFailure(status: .conflict, code: "machine_exists", message: "one of these devices is already enrolled") }
        return try Json.response(Added(invites: try picked.map { try invite($0.0, $0.1, actor: caller.name, run: id) }), status: .created)
    }

    private func invite(_ item: AddScanItem, _ found: ScanResultRow, actor: String, run: Int) throws -> Invite {
        let now = services.clock.now
        let made: (token: String, expires: Date)
        do {
            made = try services.enrollments.create(machineName: item.name, expectedIp: found.ip, now: now)
        } catch EnrollmentError.machineExists {
            throw ApiFailure(status: .conflict, code: "machine_exists", message: "a machine named \(item.name) is already enrolled")
        }
        try services.audit.record(actor: actor, action: "enrollment.create", target: item.name, detail: ["from_scan": String(run), "ip": found.ip], at: now)
        return Invite(name: item.name, ip: found.ip, enrollmentToken: made.token, expiresAt: ISO8601DateFormatter().string(from: made.expires))
    }

    private func runId(_ context: RootContext) throws -> Int {
        guard let text = context.parameters.get("id"), let id = Int(text), id > 0 else { throw ApiFailure.notFound }
        return id
    }
}

private struct Started: Encodable { let id: Int; let state: String }

private struct Latest: Encodable {
    let scan: ScanRunSummary?

    enum CodingKeys: String, CodingKey { case scan }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(scan, forKey: .scan)
    }
}

private struct Invite: Encodable { let name: String; let ip: String; let enrollmentToken: String; let expiresAt: String }
private struct Added: Encodable { let invites: [Invite] }
