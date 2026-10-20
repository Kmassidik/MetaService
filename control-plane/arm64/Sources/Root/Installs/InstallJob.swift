import Foundation
import RootCore

/// One install being followed in the panel: its steps, how far it got, and why it stopped.
struct InstallJob: Encodable {
    let id: String
    let name: String
    var state: InstallState
    var steps: [InstallStep]
    var error: String?
    /// Set when the install worked but the machine says something stops it from creating VMs (for example a missing tool): the message and its fix.
    var warning: String?
}

struct InstallFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

enum InstallErrors {
    /// An install failure the operator can act on: our own message as it is, anything else with what went wrong underneath.
    static func explain(_ error: Error) -> String {
        if let failure = error as? InstallFailure { return failure.message }
        return "the install stopped: \(error.localizedDescription)"
    }
}
