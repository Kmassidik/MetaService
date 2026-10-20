import Foundation

public enum PlanScriptError: Error, Equatable {
    case missing(String)
    case unsafeContent
}

/// Turns the plan's operations into text for `sh -s` on the other computer, and builds the small scripts that go into the box (start, stop) and the one that takes it away.
/// Everything that comes from a name or a path goes through `Shell.quote`. The scripts stop at the first failure.
public enum PlanScripts {
    private static let heredocEnd = "__METASERVICE_END__"
    public static let madeBy = "metaservice"

    public static func keyMarker(_ machine: String) -> String { "metaservice-\(machine)" }

    // MARK: the program's own command lines

    public static func runArguments(_ options: RemoteInstallOptions, box: String? = nil) -> [String] {
        let state = (box ?? options.box) + "/state"
        var arguments = ["run", "--state-dir", state, "--engine", options.engine, "--port", String(options.agentPort), "--bind", "127.0.0.1",
                         "--chat-port", String(options.chatPort), "--chat-bind", "127.0.0.1", "--heartbeat-seconds", "5"]
        let limits: [(String, Int?)] = [("--ram-reserve-mb", options.settings.ramReserveMb), ("--disk-reserve-gb", options.settings.diskReserveGb),
                                        ("--ram-allowance-mb", options.settings.ramAllowanceMb), ("--disk-allowance-gb", options.settings.diskAllowanceGb)]
        for (flag, value) in limits { if let value { arguments += [flag, String(value)] } }
        if options.allowScreen { arguments += ["--screen", options.engine == "simulated" ? "simulated" : "mac"] }
        return arguments
    }

    public static func enrollCommand(_ options: RemoteInstallOptions, box: String? = nil) -> String {
        let box = box ?? options.box
        let words = [box + "/bin/" + InstallPlan.programName, "enroll", "--root", options.rootURL, "--name", options.name,
                     "--enrollment-token-file", box + "/state/enroll.token", "--state-dir", box + "/state"]
        return words.map(Shell.quote).joined(separator: " ")
    }

    // MARK: what goes into the box

    public static func startScript(_ options: RemoteInstallOptions) -> String {
        let arguments = runArguments(options).map { Shell.quote(relative($0, to: options.box)) }.joined(separator: " ")
        return """
        #!/bin/sh
        # Starts the MetaService program of this box. Made by the parent. To take MetaService away, remove the machine in the dashboard (or delete this whole folder).
        cd "$(dirname "$0")" || exit 1
        if [ -f state/agent.pid ] && kill -0 "$(cat state/agent.pid)" 2>/dev/null; then echo "already running"; exit 0; fi
        nohup ./bin/\(InstallPlan.programName) \(arguments) >> logs/agent.log 2>&1 &
        echo $! > state/agent.pid
        echo "started"

        """
    }

    public static func stopScript() -> String {
        """
        #!/bin/sh
        cd "$(dirname "$0")" || exit 1
        if [ -f state/agent.pid ]; then kill "$(cat state/agent.pid)" 2>/dev/null; rm -f state/agent.pid; fi

        """
    }

    /// A path inside the box written relative to it, so start.sh keeps working if the folder is moved. Paths outside the box stay as they are.
    private static func relative(_ argument: String, to box: String) -> String {
        argument.hasPrefix(box + "/") ? String(argument.dropFirst(box.count + 1)) : argument
    }

    private struct Manifest: Encodable {
        let madeBy: String
        let version: Int
        let machine: String
        let createdAt: String
        let level: String
        let box: String
        let agentPort: Int
        let engine: String
        let createdPaths: [String]
        let keyFile: String?
        let keyMarker: String?
        let keyFileCreated: Bool
        let sshDirCreated: Bool
    }

    /// The record of what the install added. The first thing removal reads. Compact, with sorted keys, so it is the same every time.
    public static func manifest(_ options: RemoteInstallOptions, createdAt: String, before: BeforeFacts) -> String {
        let paths = [options.box, options.box + "/bin", options.box + "/state", options.box + "/logs", options.box + "/bin/" + InstallPlan.programName,
                     options.box + "/start.sh", options.box + "/stop.sh", options.box + "/manifest.json"]
        let record = Manifest(madeBy: madeBy, version: 1, machine: options.name, createdAt: createdAt, level: options.level.rawValue, box: options.box, agentPort: options.agentPort,
                              engine: options.engine, createdPaths: paths, keyFile: options.installKey ? options.sshDirectory + "/authorized_keys" : nil,
                              keyMarker: options.installKey ? keyMarker(options.name) : nil,
                              keyFileCreated: options.installKey && !before.keyFileExisted, sshDirCreated: options.installKey && !before.sshDirExisted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: (try? encoder.encode(record)) ?? Data(), as: UTF8.self)
    }

    /// The restricted authorized_keys line: it can only forward the Agent's port on that computer. No shell, no agent or X11 forwarding, nothing else.
    public static func keyLine(publicKey: String, options: RemoteInstallOptions) -> String {
        let parts = publicKey.split(separator: " ")
        let key = parts.prefix(2).joined(separator: " ")
        let listen = options.reversePort.map { ",permitlisten=\"127.0.0.1:\($0)\"" } ?? ""
        return "restrict,port-forwarding,permitopen=\"127.0.0.1:\(options.agentPort)\"\(listen),command=\"exit 1\" \(key) \(keyMarker(options.name))"
    }

    // MARK: operations to script

    /// The text for `sh -s`. The program itself (`.agentBinary`) is streamed by another command, so it is skipped here.
    public static func script(_ operations: [RemoteOperation], enrollToken: String? = nil, keyLine: String? = nil, manifest: String? = nil) throws -> String {
        var lines = ["set -eu", "umask 077"]
        for operation in operations { lines += try commands(for: operation, enrollToken: enrollToken, keyLine: keyLine, manifest: manifest) }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func commands(for operation: RemoteOperation, enrollToken: String?, keyLine: String?, manifest: String?) throws -> [String] {
        switch operation {
        case .makeFolder(let path, let mode):
            return ["mkdir -m \(mode) -- \(Shell.quote(path))"]
        case .putFile(_, _, .agentBinary):
            return []
        case .putFile(let path, let mode, .text(let text)):
            return try file(path, mode, text)
        case .putFile(let path, let mode, .enrollToken):
            guard let enrollToken else { throw PlanScriptError.missing("the enrollment token") }
            return try file(path, mode, enrollToken)
        case .putFile(let path, let mode, .manifest):
            guard let manifest else { throw PlanScriptError.missing("the manifest") }
            return try file(path, mode, manifest)
        case .run(let command), .runAsAdmin(let command):
            return [command]
        case .addKeyLine(let path):
            guard let keyLine else { throw PlanScriptError.missing("the key line") }
            return try keyCommands(path, keyLine)
        }
    }

    private static func file(_ path: String, _ mode: String, _ text: String) throws -> [String] {
        guard !text.contains(heredocEnd) else { throw PlanScriptError.unsafeContent }
        return ["cat > \(Shell.quote(path)) <<'\(heredocEnd)'", text.hasSuffix("\n") ? String(text.dropLast()) : text, heredocEnd, "chmod \(mode) \(Shell.quote(path))"]
    }

    /// Adds the line at the end of the file, after a newline if the file does not end in one. A folder or file that is missing is made, private.
    private static func keyCommands(_ path: String, _ line: String) throws -> [String] {
        guard !line.contains("\n"), !line.contains(heredocEnd) else { throw PlanScriptError.unsafeContent }
        let folder = (path as NSString).deletingLastPathComponent
        return ["[ -d \(Shell.quote(folder)) ] || mkdir -m 700 -- \(Shell.quote(folder))",
                "[ -e \(Shell.quote(path)) ] || { : > \(Shell.quote(path)); chmod 600 \(Shell.quote(path)); }",
                "if [ -s \(Shell.quote(path)) ] && [ \"$(tail -c 1 \(Shell.quote(path)) | wc -l)\" -eq 0 ]; then echo >> \(Shell.quote(path)); fi",
                "printf '%s\\n' \(Shell.quote(line)) >> \(Shell.quote(path))"]
    }

    // MARK: checks before and after

    /// Refuses to touch an existing folder: the box must not be there yet. Exit 20 means "already there".
    public static func beforeScript(_ options: RemoteInstallOptions) -> String {
        """
        set -u
        if [ -d \(Shell.quote(options.sshDirectory)) ]; then echo "ssh_dir_existed=yes"; else echo "ssh_dir_existed=no"; fi
        if [ -e \(Shell.quote(options.sshDirectory + "/authorized_keys")) ]; then echo "key_file_existed=yes"; else echo "key_file_existed=no"; fi
        if [ -e \(Shell.quote(options.box)) ]; then echo "ms-error: the folder \(options.box) already exists, so nothing was changed"; exit 20; fi
        if [ ! -d \(Shell.quote((options.box as NSString).deletingLastPathComponent)) ]; then echo "ms-error: the folder for the box does not exist"; exit 21; fi
        if [ ! -w \(Shell.quote((options.box as NSString).deletingLastPathComponent)) ]; then echo "ms-error: that user cannot write there"; exit 22; fi
        echo ok

        """
    }

    // MARK: removal

    /// Takes a box away: stops the program, removes the key line it added (by its marker), then the folder. It refuses a folder that is not a MetaService box.
    /// A key file or ssh folder the install made itself is removed again; one that was there before is left as it was, minus our line.
    /// With `rollingBack` it also takes a box that is only half installed (it has the marker, but no record yet).
    public static func removeScript(box: String, key: RemovedKey?, rollingBack: Bool = false) -> String {
        let recorded = "[ -f \(Shell.quote(box + "/manifest.json")) ] && grep -q '\"made_by\":\"\(madeBy)\"' \(Shell.quote(box + "/manifest.json"))"
        let partial = rollingBack ? " || [ -f \(Shell.quote(box + "/" + InstallPlan.partialMarker)) ]" : ""
        var lines = ["set -u",
                     "if ! { \(recorded)\(partial); }; then echo \"ms-error: that is not a MetaService box, so nothing was removed\"; exit 30; fi",
                     "if [ -x \(Shell.quote(box + "/stop.sh")) ]; then sh \(Shell.quote(box + "/stop.sh")); fi"]
        if let key { lines += keyRemoval(key) }
        lines += ["rm -rf -- \(Shell.quote(box))", "echo removed"]
        return lines.joined(separator: "\n") + "\n"
    }

    public struct RemovedKey: Equatable, Sendable {
        public let file: String
        public let marker: String
        public let fileCreated: Bool
        public let directoryCreated: Bool

        public init(file: String, marker: String, fileCreated: Bool, directoryCreated: Bool) {
            self.file = file
            self.marker = marker
            self.fileCreated = fileCreated
            self.directoryCreated = directoryCreated
        }
    }

    /// The facts about the other computer that only the run knows, read just before anything is changed.
    public struct BeforeFacts: Equatable, Sendable {
        public let sshDirExisted: Bool
        public let keyFileExisted: Bool

        public init(sshDirExisted: Bool, keyFileExisted: Bool) {
            self.sshDirExisted = sshDirExisted
            self.keyFileExisted = keyFileExisted
        }

        public static func parse(_ output: String) -> BeforeFacts {
            BeforeFacts(sshDirExisted: output.contains("ssh_dir_existed=yes"), keyFileExisted: output.contains("key_file_existed=yes"))
        }
    }

    private static func keyRemoval(_ key: RemovedKey) -> [String] {
        let file = Shell.quote(key.file), temp = Shell.quote(key.file + ".ms-tmp")
        var lines = ["if [ -f \(file) ]; then grep -vF \(Shell.quote(key.marker)) \(file) > \(temp) || true; cat \(temp) > \(file); rm -f \(temp); fi"]
        if key.fileCreated { lines.append("if [ -f \(file) ] && [ ! -s \(file) ]; then rm -f \(file); fi") }
        if key.directoryCreated { lines.append("rmdir \(Shell.quote((key.file as NSString).deletingLastPathComponent)) 2>/dev/null || true") }
        return lines
    }
}
