import Foundation
import RootCore
import RootStore

/// Brings a person's records up to date with what the machines did. Nothing runs in the background: every call of a person first settles its own
/// requests, so a VM made while nobody was asking still ends up owned, counted and (if wanted) given its public key.
extension McpService {
    /// A VM that is missing from its machine's list only counts as gone once the machine has reported in this long after the command that made it ended.
    static let goneGraceSeconds: TimeInterval = 60

    func settle(_ caller: McpCaller) {
        settleCreates(caller)
        settleActions(caller)
        settleGone(caller)
        applyPublicKeys(caller)
    }

    /// A create's command ended: the row gets its VM id, or goes away from the count when the machine could not make it.
    private func settleCreates(_ caller: McpCaller) {
        for row in (try? ownership.alive(person: caller.person.id)) ?? [] where row.workloadId == nil {
            guard let commandId = row.commandId, let command = try? commands.get(commandId) else { continue }
            if command.state == "succeeded", let workload = command.result?["workload_id"] {
                try? ownership.setWorkload(row: row.id, workload: workload)
                try? requests.finish(id: row.requestId, state: .done, result: ["machine": row.machineId, "vm": workload])
            } else if command.state == "failed" {
                try? ownership.markDeleted(row: row.id, now: clock.now)
                try? requests.finish(id: row.requestId, state: .failed, result: ["message": Self.failureText(command)])
            }
        }
    }

    /// A start, stop or delete ended. A finished delete takes the VM out of the person's count.
    private func settleActions(_ caller: McpCaller) {
        for request in (try? requests.unfinished(person: caller.person.id)) ?? [] where request.kind != .create {
            guard let commandId = request.commandId, let command = try? commands.get(commandId) else { continue }
            let target: [String: Any] = ["machine": request.params["machine"] ?? "", "vm": request.params["vm"] ?? ""]
            if command.state == "succeeded" {
                try? requests.finish(id: request.id, state: .done, result: target)
                if request.kind == .delete { forget(caller, params: request.params) }
            } else if command.state == "failed" {
                try? requests.finish(id: request.id, state: .failed, result: ["message": Self.failureText(command)])
            }
        }
    }

    private func forget(_ caller: McpCaller, params: [String: Any]) {
        guard let machine = params["machine"] as? String, let vm = params["vm"] as? String, let row = try? ownership.find(person: caller.person.id, machine: machine, workload: vm) else { return }
        try? ownership.markDeleted(row: row.id, now: clock.now)
    }

    /// A VM deleted somewhere else (the panel) must not keep a slot of the person for ever.
    private func settleGone(_ caller: McpCaller) {
        for row in (try? ownership.alive(person: caller.person.id)) ?? [] where row.workloadId != nil && isGone(row) {
            try? ownership.markDeleted(row: row.id, now: clock.now)
        }
    }

    private func isGone(_ row: McpWorkloadRow) -> Bool {
        guard let id = row.workloadId else { return false }
        guard let machine = try? machines.get(id: row.machineId, now: clock.now) else { return true }
        guard !machine.workloads.contains(where: { $0.id == id }) else { return false }
        let formatter = ISO8601DateFormatter()
        let made = row.commandId.flatMap { try? commands.get($0) }?.finishedAt.flatMap(formatter.date(from:))
        guard let made, let seen = machine.lastSeen.flatMap(formatter.date(from:)) else { return false }
        return seen > made.addingTimeInterval(Self.goneGraceSeconds)
    }

    /// Hands a create's public key to its VM once the machine lists the VM, then forgets the key (the request keeps nothing to show later).
    private func applyPublicKeys(_ caller: McpCaller) {
        for request in (try? requests.withPublicKey(person: caller.person.id)) ?? [] {
            guard let key = request.params["ssh_public_key"] as? String, let row = try? ownership.row(request: request.id), let live = liveVm(row) else { continue }
            _ = try? sshKeys.add(actor: caller.actor, machine: live.machine.id, workload: live.vm.id, publicKey: key)
            var params = request.params
            params.removeValue(forKey: "ssh_public_key")
            try? requests.setParams(id: request.id, params: params)
        }
    }

    static func failureText(_ command: CommandRow) -> String {
        command.result?["error"] ?? "the machine could not do it"
    }
}
