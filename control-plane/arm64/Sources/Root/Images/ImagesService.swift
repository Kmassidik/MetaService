import Foundation
import RootCore
import RootStore

/// Which images a machine has ready: the catalog joined with what the machine's helper says. Read only.
final class ImagesService: Sendable {
    static let helperTimeoutSeconds: TimeInterval = 10
    private static let missingRouteStatus = 404

    private let machines: MachineStore
    private let client: AgentClient
    private let clock: Clock

    init(machines: MachineStore, client: AgentClient, clock: Clock) {
        self.machines = machines
        self.client = client
        self.clock = clock
    }

    func reply(for machine: String) async throws -> MachineImagesReply {
        let summary = try machines.get(id: machine, now: clock.now)
        guard summary.state != "offline" else { return .merge(.unreachable) }
        return .merge(await ask(machine))
    }

    private func ask(_ machine: String) async -> HelperImagesAnswer {
        guard let reply = try? await client.call(machine: machine, method: "GET", path: "/v1/images", timeout: Self.helperTimeoutSeconds) else { return .unreachable }
        if reply.status == Self.missingRouteStatus { return .oldHelper }
        guard reply.status == 200, let images = HelperImage.parse(reply.json) else { return .unreachable }
        return .answered(images)
    }
}
