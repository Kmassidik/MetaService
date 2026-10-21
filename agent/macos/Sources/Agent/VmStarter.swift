import Foundation
import AgentCore

/// A VM that came up and answered: where it can be reached and how it came up.
struct StartedVm {
    let address: String?
    let mode: InitMode
}

/// Reads why a container stopped: its exit code and the last lines it and its boot log printed. Every call is a fixed argument list.
struct StoppedReasonReader: Sendable {
    let cli: ContainerCLI
    private static let quick: TimeInterval = 30

    func read(_ id: String) async -> StoppedReason {
        let inspected = (try? await cli.run(AppleContainer.inspect(id), timeout: Self.quick)).flatMap { ContainerJson.parse($0).first }
        let log = (try? await cli.run(AppleContainer.logs(id), timeout: Self.quick)) ?? Data()
        let boot = (try? await cli.run(AppleContainer.bootLogs(id), timeout: Self.quick)) ?? Data()
        return StoppedReason.read(exitCode: inspected?.exitCode, log: log, bootLog: boot)
    }
}

/// Starts a VM and only calls it started once it has answered. It tries with systemd first; if that VM quits or never answers, it removes it and tries once
/// more without systemd. When both fail it says so, with what each VM printed.
struct VmStarter: Sendable {
    let cli: ContainerCLI
    let readySeconds: Int
    let settleSeconds: Int

    private static let slow: TimeInterval = 900
    private static let quick: TimeInterval = 30
    private static let probeTimeout: TimeInterval = 10
    private static let oneSecond: UInt64 = 1_000_000_000

    private enum Attempt {
        case started(StartedVm)
        case failed(StartAttemptFailure)
    }

    func start(id: String, request: CreateWorkloadRequest, image: String) async throws -> StartedVm {
        let first = await attempt(.systemd, id: id, request: request, image: image)
        guard case .failed(let systemdFailure) = first else { return try started(first) }
        _ = try? await cli.run(AppleContainer.delete(id), timeout: Self.quick)
        let second = await attempt(.plain, id: id, request: request, image: image)
        guard case .failed(let plainFailure) = second else { return try started(second) }
        throw EngineError.notReady(StartFailure.message(systemd: systemdFailure, plain: plainFailure))
    }

    private func started(_ attempt: Attempt) throws -> StartedVm {
        guard case .started(let vm) = attempt else { throw EngineError.failed("the machine did not start") }
        return vm
    }

    private func attempt(_ mode: InitMode, id: String, request: CreateWorkloadRequest, image: String) async -> Attempt {
        do {
            _ = try await cli.run(AppleContainer.run(id: id, request: request, image: image, mode: mode), timeout: Self.slow)
        } catch {
            return .failed(.notStarted)
        }
        return await watch(id)
    }

    /// Asks every second whether the VM is still there and has finished its first start; gives up after `readySeconds`.
    private func watch(_ id: String) async -> Attempt {
        for _ in 0..<max(1, readySeconds) {
            switch await look(id) {
            case .gone, .found(_, .stopped): return .failed(.exited(await StoppedReasonReader(cli: cli).read(id)))
            case .found(_, .running): if let mode = await answer(id) { return await settle(id, mode) }
            default: break
            }
            try? await Task.sleep(nanoseconds: Self.oneSecond)
        }
        return .failed(.timedOut(seconds: readySeconds))
    }

    /// The VM answered. A short wait, then one more look, because a VM whose first process quits does so within a moment of starting.
    private func settle(_ id: String, _ mode: InitMode) async -> Attempt {
        try? await Task.sleep(nanoseconds: UInt64(settleSeconds) * Self.oneSecond)
        switch await look(id) {
        case .found(let info, .running), .found(let info, .provisioning): return .started(StartedVm(address: info.ipv4, mode: mode))
        case .unknown: return .started(StartedVm(address: nil, mode: mode))
        default: return .failed(.exited(await StoppedReasonReader(cli: cli).read(id)))
        }
    }

    private func answer(_ id: String) async -> InitMode? {
        guard let output = try? await cli.run(AppleContainer.initModeProbe(id), timeout: Self.probeTimeout) else { return nil }
        return InitMode.parse(String(decoding: output, as: UTF8.self))
    }

    private enum Look {
        case gone
        case found(ContainerInfo, WorkloadState)
        /// The tool did not answer, so nothing is known about the VM. The helper keeps waiting rather than call it failed.
        case unknown
    }

    private func look(_ id: String) async -> Look {
        guard let output = try? await cli.run(AppleContainer.listAll, timeout: Self.quick) else { return .unknown }
        guard let info = ContainerJson.parse(output).first(where: { $0.name == AppleContainer.name(for: id) }) else { return .gone }
        return .found(info, ContainerStates.workloadState(info.state))
    }
}
