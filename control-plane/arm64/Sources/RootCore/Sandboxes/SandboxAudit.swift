import Foundation

/// The audit entries sandbox keys, teams and sandboxes leave (see sandbox/README.md, phase 3). Pure string building:
/// the caller writes them through `AuditStore`.
///
/// Key entries carry the team and the prefix only. The key text and its secret never reach the audit log, a message or
/// a response after the moment the key is made.
public enum SandboxAudit {
    public static let teamCreated = "sandbox.team_create"
    public static let keyCreated = "sandbox.key_create"
    public static let keyRevoked = "sandbox.key_revoke"
    public static let sandboxCreated = "sandbox.create"
    public static let sandboxEnded = "sandbox.end"

    public static func teamDetail(name: String, limits: TeamLimits) -> [String: String] {
        ["name": name, "max_running": String(limits.maxRunning), "max_vcpu": String(limits.maxVcpu),
         "max_ram_mb": String(limits.maxRamMb), "max_sandboxes_per_hour": String(limits.maxSandboxesPerHour)]
    }

    public static func keyDetail(team: String, prefix: String) -> [String: String] {
        ["team": team, "prefix": prefix]
    }

    public static func createDetail(team: String, machine: String, template: String, shape: SandboxShape, endAt: Date) -> [String: String] {
        ["team": team, "machine": machine, "template": template, "vcpu": String(shape.vcpu), "ram_mb": String(shape.ramMb),
         "disk_mb": String(shape.diskMb), "end_at": iso(endAt)]
    }

    public static func endDetail(team: String, machine: String, reason: SandboxEndReason, seconds: Int) -> [String: String] {
        ["team": team, "machine": machine, "reason": reason.rawValue, "seconds": String(seconds)]
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
