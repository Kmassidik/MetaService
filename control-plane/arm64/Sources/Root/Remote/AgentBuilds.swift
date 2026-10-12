import Foundation

/// The MetaService programs this parent can put on other computers, by system: "darwin-arm64", "linux-x86_64", "linux-arm64".
/// The one for this Mac is the build the parent already uses; the others are files named metaservice-agent-<system> in the builds folder.
enum AgentBuilds {
    static let prefix = "metaservice-agent-"

    static func available(config: RootConfig, thisSystem: String = "darwin-" + HostSize.architecture()) -> [String: String] {
        var builds: [String: String] = [:]
        if FileManager.default.isExecutableFile(atPath: config.agentBinary) { builds[thisSystem] = config.agentBinary }
        guard let folder = config.agentBuildsDirectory, let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return builds }
        for name in names where name.hasPrefix(prefix) {
            let path = folder + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { builds[String(name.dropFirst(prefix.count))] = path }
        }
        return builds
    }
}
