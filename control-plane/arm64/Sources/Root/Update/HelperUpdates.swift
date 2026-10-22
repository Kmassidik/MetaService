import Foundation
import RootCore
import RootStore

/// The helper programs the parent can put on a machine, and what that means for each machine: is the one it runs the newest?
struct HelperUpdates: Sendable {
    /// One program the parent can install: where it is and its build.
    struct Offer: Equatable {
        let path: String
        let build: String
    }

    let config: RootConfig
    let hashes: BuildHashCache

    /// The programs by system ("darwin-arm64", "linux-x86_64", "linux-arm64"). A file that cannot be read has no build and is left out.
    func offers() -> [String: Offer] {
        AgentBuilds.available(config: config).compactMapValues { path in hashes.build(ofFileAt: path).map { Offer(path: path, build: $0) } }
    }

    func status(of machine: MachineSummary, offers: [String: Offer]) -> HelperUpdate {
        HelperUpdateRules.decide(os: machine.os, arch: machine.arch, reported: machine.agentBuild, builds: offers.mapValues(\.build))
    }

    func status(of machine: MachineSummary) -> HelperUpdate { status(of: machine, offers: offers()) }

    /// The program to send to this machine, or nil when there is none for its system.
    func offer(for machine: MachineSummary) -> Offer? {
        HelperUpdateRules.system(os: machine.os, arch: machine.arch).flatMap { offers()[$0] }
    }
}

/// A machine as the list shows it: everything the store knows, plus whether a newer helper can be put on it.
struct MachineListed: Encodable {
    let machine: MachineSummary
    let update: HelperUpdate

    private enum ExtraKeys: String, CodingKey { case update }

    func encode(to encoder: Encoder) throws {
        try machine.encode(to: encoder)
        var extra = encoder.container(keyedBy: ExtraKeys.self)
        try extra.encode(update, forKey: .update)
    }
}
