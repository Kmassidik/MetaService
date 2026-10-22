import Foundation
import RootCore
import RootStore

/// One machine as its page reads it: everything the list shows, plus what only the page needs.
/// A value the parent has not been told is null, never made up.
struct MachineDetail: Encodable {
    let machine: MachineSummary
    /// The helper's folder and port, known when the parent installed the helper over SSH.
    let box: String?
    let agentPort: Int?
    /// Null until the machine has reported once.
    let ruvio: RuvioStatus?
    /// Whether a newer helper program can be put on this machine.
    let update: HelperUpdate

    private enum ExtraKeys: String, CodingKey { case box, agentPort, ruvio, update }

    func encode(to encoder: Encoder) throws {
        try machine.encode(to: encoder)
        var extra = encoder.container(keyedBy: ExtraKeys.self)
        try extra.encode(box, forKey: .box)
        try extra.encode(agentPort, forKey: .agentPort)
        try extra.encode(ruvio, forKey: .ruvio)
        try extra.encode(update, forKey: .update)
    }
}

/// Builds the detail of a machine from the stores that know each part of it.
struct MachineDetails {
    let machines: MachineStore
    let remoteMachines: RemoteMachineStore
    let bundles: BundleStore
    let commands: CommandStore
    let updates: HelperUpdates
    let clock: Clock

    func get(id: String) throws -> MachineDetail {
        let machine = try machines.get(id: id, now: clock.now)
        let installedOverSsh = try remoteMachines.get(id)
        return MachineDetail(machine: machine, box: installedOverSsh?.box, agentPort: installedOverSsh?.agentPort, ruvio: try ruvio(of: machine), update: updates.status(of: machine))
    }

    private func ruvio(of machine: MachineSummary) throws -> RuvioStatus? {
        guard machine.lastSeen != nil else { return nil }
        let going = try commands.goingBundleCommand(machine: machine.id, workloadId: nil)
        return RuvioStatus.make(installed: machine.bundleVersion, pinned: try bundles.pinned(), going: going)
    }
}
