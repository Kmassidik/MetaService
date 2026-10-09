import Darwin
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
                                          diskReserveGb: InstallDefaults.diskReserveGb(totalGb: size.diskGb), agentReady: services.installs.agentReady, chatAvailable: chatFiles > 0,
                                          profile: Self.thisComputersProfile, computer: Computer(name: LocalMachineName.make(from: ProcessInfo.processInfo.hostName), os: "macos", arch: HostSize.architecture(), cpuCores: size.cpuCores, ramMb: size.ramMb, diskGb: size.diskGb), aiModel: services.config.aiConfigured ? services.config.aiModel : nil,
                                          vmCpu: InstallDefaults.vmCpu, vmRamMb: InstallDefaults.vmRamMb, vmDiskGb: InstallDefaults.vmDiskGb))
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
        let profile: String
        let computer: Computer
        let aiModel: String?
        let vmCpu: Int
        let vmRamMb: Int
        let vmDiskGb: Int
    }

    /// The control plane built here runs on Apple Silicon, so the computer it runs on is one.
    private static let thisComputersProfile = "apple-silicon-mac"

    /// What this computer is, read from the system, shown in the list of available computers.
    private struct Computer: Encodable {
        let name: String
        let os: String
        let arch: String
        let cpuCores: Int
        let ramMb: Int
        let diskGb: Int
    }

    private struct Started: Encodable {
        let id: String
    }
}

/// The size of the computer the control plane runs on, to suggest sensible limits in the form.
struct HostSize {
    let cpuCores: Int
    let ramMb: Int
    let diskGb: Int

    static func architecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) } }
    }

    static func read() -> HostSize {
        let disk = ((try? FileManager.default.attributesOfFileSystem(forPath: "/"))?[.systemSize] as? NSNumber)?.intValue ?? 0
        return HostSize(cpuCores: ProcessInfo.processInfo.activeProcessorCount, ramMb: Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024)), diskGb: disk / 1_000_000_000)
    }
}
