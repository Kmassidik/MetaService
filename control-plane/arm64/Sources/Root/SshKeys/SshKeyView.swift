import Foundation
import RootCore
import RootStore

/// How a person reaches the VM from their laptop. Every part is null when it is not known, so the shape never changes.
struct SshConnectView: Encodable {
    let jump: String?
    let jumpIsDefault: Bool
    let vmAddress: String?
    let command: String?

    enum CodingKeys: String, CodingKey { case jump, jumpIsDefault, vmAddress, command }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(jump, forKey: .jump)
        try box.encode(jumpIsDefault, forKey: .jumpIsDefault)
        try box.encode(vmAddress, forKey: .vmAddress)
        try box.encode(command, forKey: .command)
    }

    /// The jump is the machine's SSH address setting, or the address it was added with. The command is only built when both parts pass the strict rules again.
    init(setting: String?, office: RemoteMachine?, vmAddress: String?) {
        let reached = SshConnect.resolveJump(setting: setting, office: office.map { (user: $0.sshUser, host: $0.host, port: $0.sshPort) })
        let address = vmAddress.flatMap { SshConnect.isValidVmAddress($0) ? $0 : nil }
        jump = reached.jump
        jumpIsDefault = reached.isDefault
        self.vmAddress = address
        command = SshConnect.command(jump: reached.jump, vmAddress: address)
    }
}

/// What the panel sees of a VM's keys: who may log in as root there, whether the machine's helper has that list yet, how setting up the SSH server goes,
/// and the command to log in with.
struct SshKeyView: Encodable {
    let keys: [SshKeyRecord]
    let applied: Bool
    let sshd: String
    let sshdState: String
    let sshdMessage: String?
    let connect: SshConnectView

    enum CodingKeys: String, CodingKey { case keys, applied, sshd, sshdState, sshdMessage, connect }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(keys, forKey: .keys)
        try box.encode(applied, forKey: .applied)
        try box.encode(sshd, forKey: .sshd)
        try box.encode(sshdState, forKey: .sshdState)
        try box.encode(sshdMessage, forKey: .sshdMessage)
        try box.encode(connect, forKey: .connect)
    }
}
