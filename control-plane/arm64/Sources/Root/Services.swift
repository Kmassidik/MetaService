import Foundation
import RootCore
import RootStore

/// Everything a route needs, built once at start.
struct Services {
    let config: RootConfig
    let clock: Clock
    let machines: MachineStore
    let enrollments: EnrollmentStore
    let audit: AuditStore
    let scans: ScanStore
    let scanService: ScanService
    let secrets: SecretBox
    let commands: CommandStore
    let workloads: WorkloadService
    let bundles: BundleStore
    let chatAccess: ChatAccessStore
    let bundleService: BundleService
    let brain: BrainStore
    let brainService: BrainService
    let throttle: Throttle
    let admin: AdminStore
    let setupGate: SetupGate
    let sessions: SessionStore

    init(config: RootConfig, database: Database, secrets: SecretBox, setupGate: SetupGate, clock: Clock = SystemClock()) {
        self.config = config
        self.setupGate = setupGate
        self.clock = clock
        machines = MachineStore(database)
        enrollments = EnrollmentStore(database)
        audit = AuditStore(database)
        admin = AdminStore(database)
        sessions = SessionStore(database)
        scans = ScanStore(database)
        scanService = ScanService(config: config, clock: clock, store: scans, audit: audit)
        throttle = Throttle(clock: clock)
        self.secrets = secrets
        commands = CommandStore(database)
        bundles = BundleStore(database, directory: config.bundleDirectory ?? (config.databasePath as NSString).deletingLastPathComponent + "/bundles")
        chatAccess = ChatAccessStore(database)
        brain = BrainStore(database)
        brainService = BrainService(config: config)
        workloads = WorkloadService(machines: machines, commands: commands, audit: audit, client: AgentClient(machines: machines, secrets: secrets), clock: clock,
                                    bundles: bundles, chatAccess: chatAccess, secrets: secrets)
        bundleService = BundleService(machines: machines, commands: commands, bundles: bundles, workloads: workloads, clock: clock)
    }
}
