import Foundation
import HTTPTypes
import RootCore

/// Why Connect stopped, in words the operator can act on. None of these texts ever holds a password.
enum RemoteFailure: Error {
    case notAllowed, unreachable, noHostKey, hostKeyChanged, fingerprintMismatch, loginRefused, passwordNotAccepted, keyNotAccepted, noAnswer, timedOut, noSsh, tooManyTries
    case closed
    case machineExists, installRunning, notRemote, badOptions(String)
    case fixUnavailable, missing(MissingFailure)

    var api: ApiFailure {
        switch self {
        case .notAllowed: return ApiFailure(status: .badRequest, code: "remote_not_allowed", message: "only computers on this network can be connected (a private address)")
        case .unreachable: return ApiFailure(status: .badGateway, code: "remote_unreachable", message: "cannot reach that computer: check its address and that SSH (Remote Login) is on")
        case .noHostKey: return ApiFailure(status: .badGateway, code: "remote_no_host_key", message: "that computer did not show an SSH host key: is SSH (Remote Login) on, and is the port right?")
        case .hostKeyChanged: return ApiFailure(status: .conflict, code: "remote_host_key_changed", message: "that computer's SSH host key is not the one we trusted before. Nothing was changed; check that it is the right computer")
        case .fingerprintMismatch: return ApiFailure(status: .conflict, code: "remote_fingerprint_mismatch", message: "the host key is not the one you confirmed. Start again from the first step")
        case .loginRefused: return ApiFailure(status: .unprocessableContent, code: "remote_login_refused", message: "the login was refused: check the user name and the password")
        case .passwordNotAccepted: return ApiFailure(status: .unprocessableContent, code: "remote_login_refused", message: "the login was refused: that computer only accepts keys over SSH, not passwords, so no password can work. Use a key instead")
        case .keyNotAccepted: return ApiFailure(status: .unprocessableContent, code: "remote_login_refused", message: "the login was refused: that computer does not have MetaService's key yet. Add the key to ~/.ssh/authorized_keys of that user, then try again")
        case .noAnswer: return ApiFailure(status: .badGateway, code: "remote_no_answer", message: "logged in, but the computer did not answer the check the way a Mac or a Linux computer does")
        case .timedOut: return ApiFailure(status: .gatewayTimeout, code: "remote_timeout", message: "the computer did not answer in time")
        case .noSsh: return ApiFailure(status: .internalServerError, code: "remote_no_ssh", message: "the ssh program is missing on the control plane computer")
        case .closed: return ApiFailure(status: .badGateway, code: "remote_closed", message: "that computer closed the connection. It may be blocking repeated login attempts (OpenSSH does that after a failed login): wait a minute and try again")
        case .machineExists: return ApiFailure(status: .conflict, code: "machine_exists", message: "a machine with that name is already added")
        case .installRunning: return ApiFailure(status: .conflict, code: "install_running", message: "another install is still running")
        case .notRemote: return ApiFailure(status: .notFound, code: "not_found", message: "that machine was not added over SSH (or it was removed since), so there is no saved login to check it with")
        case .badOptions(let message): return ApiFailure(status: .badRequest, code: "invalid_input", message: message)
        case .fixUnavailable: return ApiFailure(status: .conflict, code: "remote_fix_unavailable", message: "MetaService cannot install that for you on this computer. Use the To fix line instead")
        case .missing(let failure): return Self.apiFailure(failure)
        case .tooManyTries: return ApiFailure(status: .tooManyRequests, code: "remote_too_many_tries", message: "too many tries on that computer. Wait a minute: repeated logins look like an attack on the network")
        }
    }

    /// A short fixed name for the audit log: never the text of an error, which could come from the other computer.
    var auditName: String {
        guard case .missing(let failure) = self else { return "\(self)" }
        return failure.auditName
    }

    private static func apiFailure(_ failure: MissingFailure) -> ApiFailure {
        switch failure {
        case .stopped, .unknown: return ApiFailure(status: .badGateway, code: "remote_install_failed", message: failure.message)
        default: return ApiFailure(status: .unprocessableContent, code: "remote_sudo_refused", message: failure.message)
        }
    }

    /// What ssh said (its exit status and error text, never a password) turned into the reason.
    /// `auth` is how the login was tried: a refusal that lists only keys means something different for a password than for a key.
    static func fromSsh(_ errors: String, status: Int32 = 255, auth: SshAuth? = nil) -> RemoteFailure {
        switch SshErrors.classify(status: status, errors: errors) {
        case .loginRefused: return refusal(errors, auth)
        case .hostKeyChanged: return .hostKeyChanged
        case .unreachable: return .unreachable
        case .closed: return .closed
        case .other: return .noAnswer
        }
    }

    private static func refusal(_ errors: String, _ auth: SshAuth?) -> RemoteFailure {
        guard SshErrors.offersOnlyKeys(errors), let auth else { return .loginRefused }
        if case .password = auth { return .passwordNotAccepted }
        return .keyNotAccepted
    }
}
