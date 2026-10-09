import Foundation
import RootCore
import RootStore

/// The computer the control plane runs on is the first machine. At start the Root invites it (pinned to this computer's own address) and leaves
/// the one-time token in a private file for the local Agent to pick up, so nobody copies a token by hand. Once the machine exists there is nothing to do.
enum LocalMachine {
    static let fileName = "local-agent.json"

    static func prepare(services: Services, directory: String) throws {
        let name = LocalMachineName.make(from: ProcessInfo.processInfo.hostName)
        let file = directory + "/" + fileName
        let now = services.clock.now
        guard (try? services.machines.get(id: name, now: now)) == nil else {
            try? FileManager.default.removeItem(atPath: file)
            return
        }
        let made: (token: String, expires: Date)
        do {
            made = try services.enrollments.create(machineName: name, expectedIp: "127.0.0.1", now: now)
        } catch EnrollmentError.machineExists {
            return
        }
        let data = try JSONSerialization.data(withJSONObject: ["name": name, "token": made.token])
        let temporary = file + ".new"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]), rename(temporary, file) == 0 else {
            throw ConfigError(description: "cannot write \(file)")
        }
    }
}
