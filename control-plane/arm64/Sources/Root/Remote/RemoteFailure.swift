import Foundation
import HTTPTypes
import RootCore

/// Why Connect stopped, in words the operator can act on. None of these texts ever holds a password.
enum RemoteFailure: Error {
    case notAllowed, unreachable, noHostKey, hostKeyChanged, fingerprintMismatch, loginRefused, noAnswer, timedOut, noSsh, tooManyTries
    case closed
    case parentUnreachable, machineExists, installRunning, notRemote, badOptions(String)

    var api: ApiFailure {
        switch self {
        case .notAllowed: return ApiFailure(status: .badRequest, code: "remote_not_allowed", message: "only computers on this network can be connected (a private address)")
        case .unreachable: return ApiFailure(status: .badGateway, code: "remote_unreachable", message: "cannot reach that computer: check its address and that SSH (Remote Login) is on")
        case .noHostKey: return ApiFailure(status: .badGateway, code: "remote_no_host_key", message: "that computer did not show an SSH host key: is SSH (Remote Login) on, and is the port right?")
        case .hostKeyChanged: return ApiFailure(status: .conflict, code: "remote_host_key_changed", message: "that computer's SSH host key is not the one we trusted before. Nothing was changed; check that it is the right computer")
        case .fingerprintMismatch: return ApiFailure(status: .conflict, code: "remote_fingerprint_mismatch", message: "the host key is not the one you confirmed. Start again from the first step")
        case .loginRefused: return ApiFailure(status: .unprocessableContent, code: "remote_login_refused", message: "the login was refused: check the user name and the password")
        case .noAnswer: return ApiFailure(status: .badGateway, code: "remote_no_answer", message: "logged in, but the computer did not answer the check the way a Mac or a Linux computer does")
        case .timedOut: return ApiFailure(status: .gatewayTimeout, code: "remote_timeout", message: "the computer did not answer in time")
        case .noSsh: return ApiFailure(status: .internalServerError, code: "remote_no_ssh", message: "the ssh program is missing on the control plane computer")
        case .closed: return ApiFailure(status: .badGateway, code: "remote_closed", message: "that computer closed the connection. It may be blocking repeated login attempts (OpenSSH does that after a failed login): wait a minute and try again")
        case .parentUnreachable: return ApiFailure(status: .conflict, code: "remote_parent_unreachable", message: "the parent only listens on this computer, so a computer on the network could never report in: set ROOT_AGENT_BIND in .env to this computer's address on the network and start it again")
        case .machineExists: return ApiFailure(status: .conflict, code: "machine_exists", message: "a machine with that name is already added")
        case .installRunning: return ApiFailure(status: .conflict, code: "install_running", message: "another install is still running")
        case .notRemote: return ApiFailure(status: .notFound, code: "not_found", message: "that machine was not installed over SSH")
        case .badOptions(let message): return ApiFailure(status: .badRequest, code: "invalid_input", message: message)
        case .tooManyTries: return ApiFailure(status: .tooManyRequests, code: "remote_too_many_tries", message: "too many tries on that computer. Wait a minute: repeated logins look like an attack on the network")
        }
    }

    /// What ssh said (its exit status and error text, never a password) turned into the reason.
    static func fromSsh(_ errors: String, status: Int32 = 255) -> RemoteFailure {
        switch SshErrors.classify(status: status, errors: errors) {
        case .loginRefused: return .loginRefused
        case .hostKeyChanged: return .hostKeyChanged
        case .unreachable: return .unreachable
        case .closed: return .closed
        case .other: return .noAnswer
        }
    }
}
