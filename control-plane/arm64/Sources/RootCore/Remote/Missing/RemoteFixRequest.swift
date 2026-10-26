import Foundation
import MSCore

/// "Install it for me": the login of Connect (an address, or a machine that is already added), which part to install, and the sudo password typed in the panel
/// (empty only for a login that needs none).
public struct RemoteFixRequest {
    public let target: RemoteLoginTarget
    public let login: RemoteLoginRequest.Login
    public let part: MissingPart
    public let sudoPassword: SudoPassword

    public static let longestPassword = RemoteLoginRequest.longestPassword

    public init(body: Data) throws {
        let object = try StrictObject(data: body, allowed: RemoteLoginRequest.fields.union([RemoteLoginTarget.machineField, "fix", "sudo_password"]))
        target = try RemoteLoginTarget.parse(object)
        login = try RemoteLoginRequest.login(object)
        guard let chosen = MissingPart(rawValue: try object.string("fix", maxLength: 20, minLength: 1)) else { throw InputError("fix must be vm_tool, python or gpu_toolkit") }
        part = chosen
        sudoPassword = SudoPassword(try object.optionalString("sudo_password", maxLength: Self.longestPassword) ?? "")
    }
}
