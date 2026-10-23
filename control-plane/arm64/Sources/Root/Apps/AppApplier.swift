import Foundation
import MSCore
import RootCore
import RootStore

/// Asks a machine's helper to install an app inside a VM, as a detached task: an install takes minutes, so no web request waits for it.
/// The store shows "installing" from the moment an install starts until it ends.
final class AppApplier: @unchecked Sendable {
    static let auditAction = "app.install"

    private let apps: AppStateStore
    private let client: AgentClient
    private let audit: AuditStore
    private let clock: Clock
    private let busy = NSLock()
    private var running = Set<String>()

    init(apps: AppStateStore, client: AgentClient, audit: AuditStore, clock: Clock) {
        self.apps = apps
        self.client = client
        self.audit = audit
        self.clock = clock
    }

    /// Marks the VM "installing" and runs the install in the background. Nothing happens when one is already running for this VM or when no app is wanted there.
    func start(machine: String, workload: String) {
        guard let app = try? apps.record(workload: workload, machine: machine)?.app, claim(machine: machine, workload: workload) else { return }
        do {
            try apps.begin(workload: workload, machine: machine, now: clock.now)
        } catch {
            release(machine: machine, workload: workload)
            return
        }
        Task.detached { [self] in
            defer { release(machine: machine, workload: workload) }
            await run(app: app, machine: machine, workload: workload)
        }
    }

    /// The install itself, awaited. Ends the "installing" phase whatever happens.
    func run(app: String, machine: String, workload: String) async {
        let reply = try? await client.call(machine: machine, method: "PUT", path: "/v1/workloads/\(workload)/app", body: ["app": app], timeout: AppCatalog.callSeconds)
        let finish = AppFinish(AppInstallOutcome.read(status: reply?.status, json: reply?.json, expectedApp: app))
        // Finishing can only fail when the store is busy or gone; the phase then times out by itself (AppRecord.atTime) and the heartbeat tries again.
        try? apps.finish(workload: workload, machine: machine, as: finish, now: clock.now)
        recordAudit(finish, app: app, machine: machine, workload: workload)
    }

    /// Never the installer's output: only the app, the result and the installer's checksum when it is known.
    private func recordAudit(_ finish: AppFinish, app: String, machine: String, workload: String) {
        guard let result = finish.auditResult else { return }
        var detail = ["workload": workload, "app": app, "result": result]
        detail["installer_sha256"] = finish.installerSha256
        try? audit.record(actor: "root", action: Self.auditAction, target: machine, detail: detail, at: clock.now)
    }

    private func claim(machine: String, workload: String) -> Bool {
        busy.withLock { running.insert("\(machine)/\(workload)").inserted }
    }

    private func release(machine: String, workload: String) {
        busy.withLock { _ = running.remove("\(machine)/\(workload)") }
    }
}
