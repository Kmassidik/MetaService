import Foundation
import RootCore

/// Why an update did not even start, in words the operator can act on. None of these texts holds anything that came from the other computer.
enum HelperUpdateFailure: Error {
    case loginNeeded, oldHelperCannotSelfUpdate, noBuild(String), upToDate, busy, tooManyTries

    static let loginNeededMessage = "MetaService cannot log in to this computer any more: add it again once, then updates will work."

    static let oldHelperCannotSelfUpdateMessage = "This computer's helper is too old to update itself, and the panel has no SSH login on it (it joined through Share a PC). Remove it and join again once: from then on its helper updates itself from the Update helper button."

    var api: ApiFailure {
        switch self {
        case .loginNeeded: return ApiFailure(status: .conflict, code: "login_needed", message: Self.loginNeededMessage)
        case .oldHelperCannotSelfUpdate: return ApiFailure(status: .conflict, code: "old_helper", message: Self.oldHelperCannotSelfUpdateMessage)
        case .noBuild(let reason): return ApiFailure(status: .conflict, code: "no_build", message: reason)
        case .upToDate: return ApiFailure(status: .conflict, code: "up_to_date", message: "This machine already runs the newest helper the parent has.")
        case .busy: return ApiFailure(status: .conflict, code: "machine_busy", message: "This machine is making or deleting a VM, or is already being updated. Wait until that is done.")
        case .tooManyTries: return ApiFailure.tooMany
        }
    }

    /// A short fixed name for the audit log.
    var auditName: String {
        switch self {
        case .loginNeeded: return "login_needed"
        case .oldHelperCannotSelfUpdate: return "old_helper"
        case .noBuild: return "no_build"
        case .upToDate: return "up_to_date"
        case .busy: return "machine_busy"
        case .tooManyTries: return "rate_limited"
        }
    }
}
