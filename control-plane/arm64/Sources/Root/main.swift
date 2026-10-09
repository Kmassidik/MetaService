import Foundation
import MSCore
import RootStore

do {
    let config = try ConfigLoader.load(arguments: Array(CommandLine.arguments.dropFirst()))
    try FileManager.default.createDirectory(atPath: (config.databasePath as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let database = try Database(path: config.databasePath)
    try Migrations.migrate(database)
    let secrets = try SecretBox.loadOrCreate(path: (config.databasePath as NSString).deletingLastPathComponent + "/root.key")
    let tokenWasInEnvFile = config.setupToken != nil
    let setupGate = try SetupGate.prepare(configured: config.setupToken, adminExists: AdminStore(database).isConfigured, envFile: config.envFile)
    if setupGate.isOpen {
        print("metaservice-root: first run. Create the admin login in the panel with the setup token: \(SetupGate.variable) in \(setupGate.envFile)" + (tokenWasInEnvFile ? "." : " (the Root just wrote it there, mode 600)."))
        fflush(stdout)
    }
    let services = Services(config: config, database: database, secrets: secrets, setupGate: setupGate)
    let stateDirectory = (config.databasePath as NSString).deletingLastPathComponent
    if config.localMachine { try LocalMachine.prepare(services: services, directory: stateDirectory) }
    services.workloads.resume()
    services.bundleService.start()
    let operatorApp = buildOperatorApplication(services: services)
    let agentApp = buildAgentApplication(services: services)
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operatorApp.runService() }
        group.addTask { try await agentApp.runService() }
        try await group.next()
        group.cancelAll()
    }
} catch {
    FileHandle.standardError.write(Data("metaservice-root: \(error)\n".utf8))
    exit(1)
}
