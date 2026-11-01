import Foundation

/// The pure part of `autostart` on a Mac: the helper's command line as start.sh wrote it, and the LaunchAgent that repeats it. Nothing is read or written here.
public enum AutostartPlist {
    public static let label = "io.metaservice.agent"
    public static let program = "metaservice-agent"
    /// Where a login's LaunchAgents live, under its home folder.
    public static let agentsFolder = "Library/LaunchAgents"
    /// The helper's pid file, relative to the box: start.sh writes it and the helper writes it itself, so stop.sh and the update find a helper launchd started.
    public static let pidFile = "state/agent.pid"
    public static let logFile = "logs/agent.log"
    /// launchd starts a job no sooner than this after it ended, so a helper that fails at once cannot fill the disk with its log.
    public static let throttleSeconds = 10
    private static let startLinePrefix = "nohup ./bin/\(program) "
    private static let redirect = ">>"

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noStartLine
        case notRun
        case openQuote
        public var description: String {
            switch self {
            case .noStartLine: return "start.sh has no line that starts the helper, so there is nothing to repeat at login"
            case .notRun: return "the start line in start.sh does not begin with `run`"
            case .openQuote: return "start.sh has a quote that is never closed"
            }
        }
    }

    /// The words after `nohup ./bin/metaservice-agent` in start.sh, as the program receives them (the first is `run`).
    public static func startArguments(startScript: String) throws -> [String] {
        let lines = startScript.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let line = lines.first(where: { $0.hasPrefix(startLinePrefix) }) else { throw Failure.noStartLine }
        let words = try shellWords(String(line.dropFirst(startLinePrefix.count)))
        let arguments = Array(words.prefix(while: { $0 != redirect }))
        guard arguments.first == "run" else { throw Failure.notRun }
        return arguments
    }

    /// One shell line split into words the way `sh` reads quotes and backslashes. Nothing is expanded.
    static func shellWords(_ line: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var started = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped { current.append(character); escaped = false; continue }
            if let open = quote, character == open { quote = nil; continue }
            if quote == "\"" && character == "\\" { escaped = true; continue }
            if quote != nil { current.append(character); continue }
            switch character {
            case "'", "\"": quote = character; started = true
            case "\\": escaped = true; started = true
            case _ where character.isWhitespace:
                if started { words.append(current); current = ""; started = false }
            default: current.append(character); started = true
            }
        }
        guard quote == nil else { throw Failure.openQuote }
        if started { words.append(current) }
        return words
    }

    /// The LaunchAgent, built as a dictionary and serialized, never by joining text. It restarts the helper only when it fails: a clean stop by stop.sh (SIGTERM, exit 0)
    /// stays stopped, which an update depends on. No UserName: a LaunchAgent is always its login's.
    public static func plistData(box: String, arguments: [String]) throws -> Data {
        let log = box + "/" + logFile
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [box + "/bin/" + program] + arguments,
            "WorkingDirectory": box,
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ThrottleInterval": throttleSeconds,
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
        return try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    }
}
