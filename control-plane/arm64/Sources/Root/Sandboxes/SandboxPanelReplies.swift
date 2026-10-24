import Foundation
import RootStore

/// What the panel's sandbox pages read (see `sandbox/README.md`, phase 3). Encoded with the panel's snake_case names and
/// times as ISO 8601 UTC. Nothing here ever carries a key text or a secret, except `SandboxKeyMade.key`, which is the one
/// answer that shows a new key on its way out.

struct SandboxKeyList: Encodable {
    let keys: [SandboxKeyListed]
}

/// One key as the list shows it: enough to tell two keys apart, never enough to call the API.
struct SandboxKeyListed: Encodable {
    let id: String
    let team: String
    let teamName: String
    let prefix: String
    let createdAt: String
    let lastUsedAt: String?
    let revokedAt: String?

    init(record: ApiKeyRecord, teamName: String) {
        id = record.id
        team = record.team
        self.teamName = teamName
        prefix = record.prefix
        createdAt = SandboxPanelTime.iso(record.createdAt)
        lastUsedAt = record.lastUsedAt.map(SandboxPanelTime.iso)
        revokedAt = record.revokedAt.map(SandboxPanelTime.iso)
    }
}

/// The one answer that carries a key's text. It is shown once and never returned again.
struct SandboxKeyMade: Encodable {
    let id: String
    let team: String
    let teamName: String
    let prefix: String
    let key: String
    let createdAt: String
}

struct SandboxLiveList: Encodable {
    let sandboxes: [SandboxListed]
}

/// One live sandbox, across every team: where it runs, what it holds and when it ends.
struct SandboxListed: Encodable {
    let id: String
    let team: String
    let teamName: String
    let machine: String
    let state: String
    let template: String
    let vcpu: Int
    let ramMb: Int
    let diskMb: Int
    let createdAt: String
    let endAt: String

    init(record: SandboxRecord, teamName: String) {
        id = record.id
        team = record.team
        self.teamName = teamName
        machine = record.machine
        state = record.state.rawValue
        template = record.template
        vcpu = record.vcpu
        ramMb = record.ramMb
        diskMb = record.diskMb
        createdAt = SandboxPanelTime.iso(record.createdAt)
        endAt = SandboxPanelTime.iso(record.endAt)
    }
}

struct SandboxUsageReply: Encodable {
    /// The window the numbers cover: whole days before `endsAt`.
    let days: Int
    let startsAt: String
    let endsAt: String
    let teams: [SandboxUsageTeam]
}

/// One team's finished runs in the window, added up the way `SandboxUsageMath` counts them.
struct SandboxUsageTeam: Encodable {
    let team: String
    let teamName: String
    let sandboxes: Int
    let seconds: Int
    let vcpuSeconds: Int
    let ramMbSeconds: Int

    init(record: TeamUsageTotals, teamName: String) {
        team = record.team
        self.teamName = teamName
        sandboxes = record.sandboxes
        seconds = record.totals.seconds
        vcpuSeconds = record.totals.vcpuSeconds
        ramMbSeconds = record.totals.ramMbSeconds
    }
}

/// One way to write a moment, so every reply of these pages agrees: `2026-10-24T09:30:00Z`.
enum SandboxPanelTime {
    static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
