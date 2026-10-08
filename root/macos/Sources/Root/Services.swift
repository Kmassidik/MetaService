import Foundation
import RootCore
import RootStore

/// Everything a route needs, built once at start.
struct Services {
    let config: RootConfig
    let clock: Clock
    let machines: MachineStore
    let enrollments: EnrollmentStore
    let sessions: SessionStore
    let audit: AuditStore
    let scans: ScanStore
    let scanService: ScanService
    let secrets: SecretBox
    let commands: CommandStore
    let workloads: WorkloadService
    let throttle: Throttle
    let google: GoogleAuth

    init(config: RootConfig, database: Database, secrets: SecretBox, clock: Clock = SystemClock()) {
        self.config = config
        self.clock = clock
        machines = MachineStore(database)
        enrollments = EnrollmentStore(database)
        sessions = SessionStore(database)
        audit = AuditStore(database)
        scans = ScanStore(database)
        scanService = ScanService(config: config, clock: clock, store: scans, audit: audit)
        throttle = Throttle(clock: clock)
        google = GoogleAuth(config: config, clock: clock)
        self.secrets = secrets
        commands = CommandStore(database)
        workloads = WorkloadService(machines: machines, commands: commands, audit: audit, client: AgentClient(machines: machines, secrets: secrets), clock: clock)
    }
}
