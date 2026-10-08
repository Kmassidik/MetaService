import Foundation
import AgentCore

struct ConfigError: Error, CustomStringConvertible {
    let description: String
}

enum Verb {
    case run
    case enroll(root: String, name: String, tokenFile: String?)
}

/// Settings from the command line. Secrets never go on the command line: the enrollment token comes from a file or an env variable.
struct AgentConfig {
    var command = Verb.run
    var stateDirectory = ("~/.metaservice-agent" as NSString).expandingTildeInPath
    var port = 9101
    var bind = "127.0.0.1"
    var engineName = "simulated"
    var reserveRamMb: Int?
    var reserveDiskGb: Int?
    var ramAllowanceMb: Int?
    var diskAllowanceGb: Int?
    var badTokenLimit = 10

    var tokenFile: String { stateDirectory + "/agent.token" }
    var settingsFile: String { stateDirectory + "/agent.json" }

    static let version = "0.1.0"
    private static let valued = ["--state-dir", "--port", "--bind", "--engine", "--ram-reserve-mb", "--disk-reserve-gb", "--ram-allowance-mb",
                                 "--disk-allowance-gb", "--bad-token-limit", "--root", "--name", "--enrollment-token-file"]

    static func parse(_ arguments: [String]) throws -> AgentConfig {
        var config = AgentConfig()
        var rest = arguments
        let verb = rest.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "run"
        if rest.first == verb { rest.removeFirst() }
        let options = try options(rest)
        try config.apply(options)
        switch verb {
        case "run": config.command = .run
        case "enroll": config.command = try enrollCommand(options)
        default: throw ConfigError(description: "unknown command \(verb); use run or enroll")
        }
        return config
    }

    private static func options(_ arguments: [String]) throws -> [String: String] {
        var found: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            guard valued.contains(arguments[index]), index + 1 < arguments.count else { throw ConfigError(description: "unknown or incomplete option \(arguments[index])") }
            found[arguments[index]] = arguments[index + 1]
            index += 2
        }
        return found
    }

    private static func enrollCommand(_ options: [String: String]) throws -> Verb {
        guard let root = options["--root"], let name = options["--name"] else { throw ConfigError(description: "enroll needs --root and --name") }
        return .enroll(root: root, name: name, tokenFile: options["--enrollment-token-file"])
    }

    private mutating func apply(_ options: [String: String]) throws {
        stateDirectory = options["--state-dir"] ?? stateDirectory
        bind = options["--bind"] ?? bind
        engineName = options["--engine"] ?? engineName
        guard ["simulated", "apple"].contains(engineName) else { throw ConfigError(description: "--engine must be simulated or apple") }
        port = try number(options["--port"], range: 1...65535) ?? port
        reserveRamMb = try number(options["--ram-reserve-mb"], range: 0...100_000_000)
        reserveDiskGb = try number(options["--disk-reserve-gb"], range: 0...100_000_000)
        ramAllowanceMb = try number(options["--ram-allowance-mb"], range: 1...100_000_000)
        diskAllowanceGb = try number(options["--disk-allowance-gb"], range: 1...100_000_000)
        badTokenLimit = try number(options["--bad-token-limit"], range: 1...1_000_000) ?? badTokenLimit
    }

    private func number(_ text: String?, range: ClosedRange<Int>) throws -> Int? {
        guard let text else { return nil }
        guard let value = Int(text), range.contains(value) else { throw ConfigError(description: "\(text) is not a number between \(range.lowerBound) and \(range.upperBound)") }
        return value
    }
}
