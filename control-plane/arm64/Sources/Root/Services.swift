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
    let installs: InstallService
    let machineSettings: MachineSettingsStore
    let localAgents: LocalAgentSupervisor
    let remote: RemoteService
    let remoteSsh: RemoteSsh
    let tunnelPorts = TunnelPorts()
    let tunnels: TunnelSupervisor
    let remoteMachines: RemoteMachineStore
    let remoteInstalls: RemoteInstallService
    let screens: ScreenService

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
        workloads = WorkloadService(machines: machines, commands: commands, audit: audit, client: AgentClient(machines: machines, secrets: secrets, tunnels: tunnelPorts), clock: clock,
                                    bundles: bundles, chatAccess: chatAccess, secrets: secrets)
        bundleService = BundleService(machines: machines, commands: commands, bundles: bundles, workloads: workloads, clock: clock)
        machineSettings = MachineSettingsStore(database)
        localAgents = LocalAgentSupervisor(store: LocalAgentStore(database))
        remoteSsh = RemoteSsh(parts: .init(config: config, clock: clock, keys: RemoteKeyStore(database), secrets: secrets, throttle: throttle))
        remote = RemoteService(ssh: remoteSsh, config: config, audit: audit, clock: clock)
        remoteMachines = RemoteMachineStore(database)
        tunnels = TunnelSupervisor(ssh: remoteSsh, remoteMachines: remoteMachines, ports: tunnelPorts, clock: clock)
        remoteInstalls = RemoteInstallService(parts: .init(config: config, clock: clock, ssh: remoteSsh, machines: machines, enrollments: enrollments, audit: audit, remoteMachines: remoteMachines,
                                                           settings: machineSettings, chatAccess: chatAccess, tunnels: tunnels))
        screens = ScreenService(client: AgentClient(machines: machines, secrets: secrets, tunnels: tunnelPorts), audit: audit, clock: clock)
        installs = InstallService(parts: .init(config: config, clock: clock, machines: machines, enrollments: enrollments, audit: audit, commands: commands, bundles: bundles, workloads: workloads, settings: machineSettings),
                                  supervisor: localAgents)
    }
}
