import Foundation
import RootStore

do {
    let config = try ConfigLoader.load(arguments: Array(CommandLine.arguments.dropFirst()))
    try FileManager.default.createDirectory(atPath: (config.databasePath as NSString).deletingLastPathComponent,
                                            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let database = try Database(path: config.databasePath)
    try Migrations.migrate(database)
    let app = buildApplication(services: Services(config: config, database: database))
    try await app.runService()
} catch {
    FileHandle.standardError.write(Data("metaservice-root: \(error)\n".utf8))
    exit(1)
}
