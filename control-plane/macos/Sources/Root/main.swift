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
    let services = Services(config: config, database: database, secrets: secrets)
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
