import Foundation

/// Where the content of a file comes from when the plan is carried out.
public enum PlanSource: Equatable, Sendable {
    case text(String)
    /// The one-time enrollment token, known only when the plan runs. It is sent inside the encrypted SSH session, never on a command line.
    case enrollToken
    /// The MetaService program for that system, streamed as it is.
    case agentBinary
    /// The record of what the install added: written last, with the facts only the run knows (was the key file there before?).
    case manifest
}

/// One small thing done on the other computer. The whole install is a list of these, so each can be described to the operator first, and undone.
public enum RemoteOperation: Equatable, Sendable {
    case makeFolder(path: String, mode: String)
    case putFile(path: String, mode: String, source: PlanSource)
    case run(command: String)
    /// Adds one marked, restricted line for the parent's key to an authorized_keys file. The line is built when the plan runs.
    case addKeyLine(file: String)
    case runAsAdmin(command: String)
}

public struct PlannedStep: Equatable, Sendable {
    public let id: String
    public let label: String
    /// What this step changes on that computer, in plain words: what the operator reads in "What will change".
    public let changes: [String]
    public let operations: [RemoteOperation]
}

/// The install of one machine, as the operator sees it and the parent carries it out. Level "folder": everything goes into one folder the install makes,
/// plus (only if allowed) one restricted line in the user's authorized_keys. Nothing that exists is modified, upgraded or removed.
public struct InstallPlan: Equatable, Sendable {
    public let options: RemoteInstallOptions
    public let steps: [PlannedStep]

    public static let programName = "metaservice-agent"
    /// Lives in the box while the install is under way and is deleted when the record is written. A box that has it can be rolled back, one that does not and has no record is not ours.
    public static let partialMarker = ".partial"

    public static func make(_ options: RemoteInstallOptions, agentSize: Int?) throws -> InstallPlan {
        let options = try options.validated()
        let box = options.box
        var steps = [folder(box), agent(box, size: agentSize), enroll(options), start(options)]
        if options.installKey { steps.append(key(options)) }
        steps.append(manifest(options))
        return InstallPlan(options: options, steps: steps)
    }

    /// Every path the install creates, which is what removal deletes and what the manifest lists.
    public var createdPaths: [String] {
        steps.flatMap(\.operations).compactMap { operation in
            switch operation {
            case .makeFolder(let path, _): return path
            case .putFile(let path, _, _): return path
            default: return nil
            }
        }
    }

    // MARK: steps

    private static func folder(_ box: String) -> PlannedStep {
        let folders = [box, box + "/bin", box + "/state", box + "/logs"]
        return PlannedStep(id: "folder", label: "Make the box folder", changes: ["Create the folder \(box) (with bin, state and logs inside). It is new: nothing in it exists yet."],
                           operations: folders.map { .makeFolder(path: $0, mode: "700") } + [.putFile(path: box + "/" + partialMarker, mode: "600", source: .text("being installed\n"))])
    }

    private static func agent(_ box: String, size: Int?) -> PlannedStep {
        let how = size.map { "Copy the MetaService program (\($0 / 1_048_576) MB) to \(box)/bin, and check it arrived whole." } ?? "Copy the MetaService program to \(box)/bin, and check it arrived whole."
        return PlannedStep(id: "agent", label: "Copy the MetaService program", changes: [how],
                           operations: [.putFile(path: box + "/bin/" + programName, mode: "700", source: .agentBinary)])
    }

    private static func enroll(_ options: RemoteInstallOptions) -> PlannedStep {
        let token = options.box + "/state/enroll.token"
        return PlannedStep(id: "enroll", label: "Enroll it with the parent",
                           changes: ["Introduce it to the parent at \(options.rootURL) with a one-time token that is used once and then deleted."] + (options.reversePort == nil ? [] : ["The way to the parent goes back through the SSH connection itself, so the parent does not listen on your network."]),
                           operations: [.putFile(path: token, mode: "600", source: .enrollToken), .run(command: PlanScripts.enrollCommand(options)), .run(command: "rm -f -- " + Shell.quote(token))])
    }

    private static func start(_ options: RemoteInstallOptions) -> PlannedStep {
        let box = options.box
        return PlannedStep(id: "start", label: "Start the program",
                           changes: ["Write \(box)/start.sh and \(box)/stop.sh, then start the program. It listens only on 127.0.0.1:\(options.agentPort) of that computer, so nothing else on the network can reach it.",
                                     "It does not start again by itself after a restart of that computer: run \(box)/start.sh."],
                           operations: [.putFile(path: box + "/start.sh", mode: "700", source: .text(PlanScripts.startScript(options))),
                                        .putFile(path: box + "/stop.sh", mode: "700", source: .text(PlanScripts.stopScript())),
                                        .run(command: "sh " + Shell.quote(box + "/start.sh"))])
    }

    private static func key(_ options: RemoteInstallOptions) -> PlannedStep {
        let file = options.sshDirectory + "/authorized_keys"
        return PlannedStep(id: "key", label: "Allow the parent's tunnel",
                           changes: ["Add ONE line to \(file) for a key made for this machine. The line is marked \(PlanScripts.keyMarker(options.name)) and is restricted: it can only forward the Agent's port \(options.agentPort)\(options.reversePort.map { " and the way back to the parent (port \($0))" } ?? ""), no shell, nothing else.",
                                     "This is the only change to a file that already exists. Removing the machine removes the line again."],
                           operations: [.addKeyLine(file: file)])
    }

    private static func manifest(_ options: RemoteInstallOptions) -> PlannedStep {
        PlannedStep(id: "manifest", label: "Write the record", changes: ["Write \(options.box)/manifest.json: a list of everything this install added, so it can be removed exactly."],
                    operations: [.putFile(path: options.box + "/manifest.json", mode: "600", source: .manifest), .run(command: "rm -f -- " + Shell.quote(options.box + "/" + partialMarker))])
    }
}
