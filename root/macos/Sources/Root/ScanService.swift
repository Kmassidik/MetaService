import Foundation
import RootCore
import RootStore

struct ScanSetup: Encodable {
    let subnet: String?
    let routerConfigured: Bool
    let nmapAvailable: Bool
}

/// Finds machines on the Root's own subnet: the router first, then nmap, then the ARP table. Read only; it never adds anything.
final class ScanService: @unchecked Sendable {
    private let config: RootConfig
    private let clock: Clock
    private let store: ScanStore
    private let audit: AuditStore
    private let router: RouterOSClient?
    private static let sweepSeconds: TimeInterval = 120
    private static let probeSeconds: TimeInterval = 60
    private static let probeBatch = 100
    private static let nmapSearch = ["/opt/homebrew/bin/nmap", "/usr/local/bin/nmap", "/usr/bin/nmap", "/run/current-system/sw/bin/nmap"]

    init(config: RootConfig, clock: Clock, store: ScanStore, audit: AuditStore) {
        self.config = config
        self.clock = clock
        self.store = store
        self.audit = audit
        router = RouterOSClient(config: config)
    }

    var subnet: Subnet? { config.scanSubnet ?? SubnetDetector.detect() }

    func setup() -> ScanSetup {
        ScanSetup(subnet: subnet?.description, routerConfigured: router != nil, nmapAvailable: nmapExecutable() != nil)
    }

    /// Starts a run in the background and returns its id. Refuses when there is no subnet or a run is already going.
    func begin(actor: String) throws -> Int {
        guard let subnet else { throw ApiFailure(status: .serviceUnavailable, code: "no_subnet", message: "no private network found; set SCAN_SUBNET in the Root's env file") }
        let runId: Int
        do {
            runId = try store.start(actor: actor, subnet: subnet.description, now: clock.now)
        } catch ScanError.alreadyRunning {
            throw ApiFailure(status: .conflict, code: "scan_running", message: "a scan is already running")
        }
        Task.detached { [self] in await perform(runId: runId, subnet: subnet, actor: actor) }
        return runId
    }

    // MARK: the run

    private func perform(runId: Int, subnet: Subnet, actor: String) async {
        var sources: [String: String] = [:]
        let fromRouter = await readRouter(subnet, &sources)
        let swept = await sweep(subnet, &sources)
        let live = Set((fromRouter.map(\.ip) + swept.map(\.ip)).filter(subnet.contains))
        let withAgent = await probeAgentPort(live, &sources)
        let hosts = swept.map { host in NmapHost(ip: host.ip, mac: host.mac, vendor: host.vendor, hostname: host.hostname, agentPortOpen: withAgent.contains(host.ip)) }
            + live.subtracting(swept.map(\.ip)).filter(withAgent.contains).map { NmapHost(ip: $0, mac: nil, vendor: nil, hostname: nil, agentPortOpen: true) }
        let arp = await readArp(&sources)
        let found = ScanMerge.merge(router: fromRouter, nmap: hosts, arp: arp, subnet: subnet)
        await record(runId: runId, actor: actor, found: found, sources: sources)
    }

    private func record(runId: Int, actor: String, found: [ScanFinding], sources: [String: String]) async {
        let anySource = sources.values.contains("ok")
        let now = clock.now
        do {
            if anySource { try store.finish(runId: runId, findings: found, sources: sources, now: now) } else { try store.fail(runId: runId, sources: sources, now: now) }
            try audit.record(actor: actor, action: "scan.run", target: String(runId), detail: sources.merging(["found": String(found.count)]) { $1 }, at: now)
        } catch {
            FileHandle.standardError.write(Data("scan \(runId): could not save results\n".utf8))
        }
    }

    private func readRouter(_ subnet: Subnet, _ sources: inout [String: String]) async -> [RouterEntry] {
        guard let router else { sources["router"] = "not_configured"; return [] }
        guard let host = config.routerURL.flatMap({ URL(string: $0)?.host }), subnet.contains(host) else { sources["router"] = "outside_subnet"; return [] }
        do {
            let entries = try await router.entries()
            sources["router"] = "ok"
            return entries
        } catch RouterFailure.refused(let code) {
            sources["router"] = "refused_\(code)"
        } catch {
            sources["router"] = "unreachable"
        }
        return []
    }

    private func sweep(_ subnet: Subnet, _ sources: inout [String: String]) async -> [NmapHost] {
        guard let nmap = nmapExecutable() else { sources["nmap"] = "missing"; return [] }
        let arguments = ["-sn", "-n", "-T4", "--max-retries", "1", "--host-timeout", "5s", "-oX", "-", subnet.description]
        do {
            sources["nmap"] = "ok"
            return NmapXml.hosts(from: try await CommandRunner.run(nmap, arguments, timeout: Self.sweepSeconds), agentPort: nil)
        } catch {
            sources["nmap"] = "failed"
            return []
        }
    }

    /// Which of the live addresses answer on the Agent port. Addresses are checked IPv4 text, so none can look like an option.
    private func probeAgentPort(_ live: Set<String>, _ sources: inout [String: String]) async -> Set<String> {
        guard let nmap = nmapExecutable(), !live.isEmpty else { return [] }
        var open = Set<String>()
        for batch in live.sorted().chunked(Self.probeBatch) {
            let arguments = ["-Pn", "-n", "-T4", "--max-retries", "1", "--host-timeout", "5s", "-p", String(config.agentPort), "--open", "-oX", "-"] + batch
            guard let data = try? await CommandRunner.run(nmap, arguments, timeout: Self.probeSeconds) else { sources["agent_probe"] = "failed"; continue }
            open.formUnion(NmapXml.hosts(from: data, agentPort: config.agentPort).filter(\.agentPortOpen).map(\.ip))
        }
        sources["agent_probe"] = sources["agent_probe"] ?? "ok"
        return open
    }

    private func readArp(_ sources: inout [String: String]) async -> [String: String] {
        guard let data = try? await CommandRunner.run(config.arpPath, ["-an"], timeout: 10) else { sources["arp"] = "failed"; return [:] }
        sources["arp"] = "ok"
        return ArpTable.parse(String(decoding: data, as: UTF8.self))
    }

    /// An nmap named in the env file is the only one used; otherwise the usual places are searched.
    private func nmapExecutable() -> String? {
        let candidates = config.nmapPath.map { [$0] } ?? Self.nmapSearch
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
