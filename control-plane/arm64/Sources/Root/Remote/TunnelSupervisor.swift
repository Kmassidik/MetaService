import Darwin
import Foundation
import MSCore
import RootCore
import RootStore

struct TunnelStatus: Encodable {
    let state: TunnelState
    /// When the state last changed.
    let since: String
    let localPort: Int?
    /// How many times in a row the tunnel could not be opened.
    let failures: Int
}

/// Keeps one SSH tunnel open to every machine that was installed with a key: from a local port of the parent to the Agent's loopback port on that computer. When a tunnel drops it is
/// opened again after a wait that grows (so a computer that is switched off is not hammered with logins). While a tunnel is down, calls to that machine fail; they never go around it.
final class TunnelSupervisor: @unchecked Sendable {
    private struct Slot {
        var task: Task<Void, Never>
        var process: Process?
        var status: TunnelStatus
    }

    private let ssh: RemoteSsh
    private let remoteMachines: RemoteMachineStore
    private let ports: TunnelPorts
    private let clock: Clock
    private let lock = NSLock()
    private var slots: [String: Slot] = [:]

    private static let readySeconds = 10.0
    private static let pollSeconds = 0.2
    private static let healthSeconds = 2.0

    init(ssh: RemoteSsh, remoteMachines: RemoteMachineStore, ports: TunnelPorts, clock: Clock) {
        self.ssh = ssh
        self.remoteMachines = remoteMachines
        self.ports = ports
        self.clock = clock
    }

    /// At start: a tunnel for every machine that has a key.
    func resume() {
        for record in (try? remoteMachines.all()) ?? [] where record.keyName != nil { ensure(record) }
    }

    func ensure(_ record: RemoteMachine) {
        guard record.keyName != nil else { return }
        ports.expect(record.machine)
        lock.withLock {
            guard slots[record.machine] == nil else { return }
            slots[record.machine] = Slot(task: Task.detached { [self] in await keepOpen(record) }, process: nil, status: status(.connecting, port: nil, failures: 0))
        }
    }

    func forget(_ machine: String) {
        let slot = lock.withLock { slots.removeValue(forKey: machine) }
        slot?.task.cancel()
        slot?.process?.terminate()
        ports.forget(machine)
    }

    func stopAll() {
        for machine in lock.withLock({ Array(slots.keys) }) { forget(machine) }
    }

    func status(of machine: String) -> TunnelStatus? { lock.withLock { slots[machine]?.status } }

    /// True once the tunnel of this machine is open (or after `seconds`, false).
    func waitUntilConnected(_ machine: String, seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 5) {
            if status(of: machine)?.state == .connected { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    // MARK: the loop

    private func keepOpen(_ record: RemoteMachine) async {
        var failures = 0
        while !Task.isCancelled {
            update(record.machine, .connecting, port: nil, failures: failures)
            let wasUp = await openOnce(record)
            ports.close(record.machine)
            failures = wasUp ? 1 : failures + 1
            update(record.machine, .disconnected, port: nil, failures: failures)
            try? await Task.sleep(nanoseconds: UInt64(TunnelBackoff.delay(afterFailures: failures) * 1_000_000_000))
        }
    }

    /// Opens the tunnel and returns when it has ended. True when it was open at some point.
    private func openOnce(_ record: RemoteMachine) async -> Bool {
        guard let name = record.keyName, let key = try? ssh.parts.keys.get(name), let target = try? RemoteTarget(host: record.host, port: record.sshPort, user: record.sshUser),
              let credentials = try? await ssh.keyCredentials(key), case .key(let keyPath) = credentials.auth, let local = Self.freePort() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = SshArguments.tunnel(target: target, keyPath: keyPath, knownHosts: ssh.pins.path, localPort: local, remotePort: record.agentPort,
                                                  reversePort: ParentUrl.reversePort(listenPort: ssh.parts.config.agentListenPort, target: HostResolver.ipv4(record.host) ?? record.host))
        process.environment = SshProcess.baseEnvironment.merging(credentials.environment) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        lock.withLock { slots[record.machine]?.process = process }
        return await withTaskCancellationHandler {
            let up = await Self.waitUntilListening(local, process: process)
            if up {
                ports.open(record.machine, port: local)
                update(record.machine, .connected, port: local, failures: 0)
            }
            if up { await Self.waitUntilGone(local, process: process) }
            return up
        } onCancel: { process.terminate() }
    }

    // MARK: pieces

    private func update(_ machine: String, _ state: TunnelState, port: Int?, failures: Int) {
        lock.withLock { slots[machine]?.status = status(state, port: port, failures: failures) }
    }

    private func status(_ state: TunnelState, port: Int?, failures: Int) -> TunnelStatus {
        TunnelStatus(state: state, since: ISO8601DateFormatter().string(from: clock.now), localPort: port, failures: failures)
    }

    private static func waitUntilListening(_ port: Int, process: Process) async -> Bool {
        for _ in 0..<Int(readySeconds / pollSeconds) {
            guard process.isRunning else { return false }
            if accepts(port) { return true }
            try? await Task.sleep(nanoseconds: UInt64(pollSeconds * 1_000_000_000))
        }
        return false
    }

    /// Returns when the ssh program has ended, or when its local port stops answering (a program that was killed may not be noticed as ended; one that hangs is ended here).
    private static func waitUntilGone(_ port: Int, process: Process) async {
        while process.isRunning, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(healthSeconds * 1_000_000_000))
            if !accepts(port) { process.terminate(); return }
        }
    }

    private static func accepts(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }

    /// A free port on loopback, found by asking the system for one.
    private static func freePort() -> Int? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { return nil }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        return named == 0 ? Int(UInt16(bigEndian: address.sin_port)) : nil
    }
}
