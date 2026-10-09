import Foundation
import Hummingbird
import RootCore

/// The Add machine form: what to suggest, start an install, and follow it.
struct InstallRoutes {
    let services: Services
    let guards: Guards

    static let installsPerMinute = 5

    func register(on group: RouterGroup<RootContext>) {
        group.get("/api/installs/defaults", use: defaults)
        group.post("/api/installs", use: start)
        group.get("/api/installs/{id}", use: progress)
    }

    func defaults(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        let size = HostSize.read()
        let chatFiles = (try? services.bundles.overview(now: services.clock.now).bundles.count) ?? 0
        return try Json.response(Defaults(name: LocalMachineName.make(from: ProcessInfo.processInfo.hostName), ramReserveMb: InstallDefaults.ramReserveMb(totalMb: size.ramMb),
                                          diskReserveGb: InstallDefaults.diskReserveGb(totalGb: size.diskGb), agentReady: services.installs.agentReady, chatAvailable: chatFiles > 0))
    }

    func start(_ request: Request, context: RootContext) async throws -> Response {
        let caller = try guards.operatorWrite(request)
        try guards.limit("install", per: context, max: Self.installsPerMinute, seconds: 60)
        let body = try InstallRequest(body: try await guards.body(request))
        return try Json.response(Started(id: try services.installs.start(body, actor: caller.name)), status: .accepted)
    }

    func progress(_ request: Request, context: RootContext) async throws -> Response {
        _ = try guards.operatorRead(request)
        guard let id = context.parameters.get("id"), let job = services.installs.job(id) else { throw ApiFailure.notFound }
        return try Json.response(job)
    }

    private struct Defaults: Encodable {
        let name: String
        let ramReserveMb: Int
        let diskReserveGb: Int
        let agentReady: Bool
        let chatAvailable: Bool
    }

    private struct Started: Encodable {
        let id: String
    }
}

/// The size of the computer the control plane runs on, to suggest sensible limits in the form.
struct HostSize {
    let ramMb: Int
    let diskGb: Int

    static func read() -> HostSize {
        let disk = ((try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemSize] as? NSNumber)?.intValue ?? 0
        return HostSize(ramMb: Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)), diskGb: disk / 1_000_000_000)
    }
}
