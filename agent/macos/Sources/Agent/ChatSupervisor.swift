import Darwin
import Foundation

/// Runs the chat service on this machine as a child of the Agent, and starts it again if it stops. When the Agent stops, so does the chat.
/// The child gets its own process group and the whole group is stopped, because the system python3 is a shim that can start the real python as a grandchild.
/// The child is started with posix_spawn so it begins with default signal handling (an Agent that ignores SIGTERM must not pass that on),
/// and it is watched with waitpid, not through Foundation's Process, which can hang when a child is stopped at the wrong moment.
actor ChatSupervisor {
    private var pid: pid_t = 0
    private var wanted = false
    private var generation = 0
    private var restarts = 0
    private let python: String
    private let logPath: String
    private static let firstDelay: UInt64 = 2
    private static let longestDelay: UInt64 = 30
    private static let maxLogBytes = 1_000_000
    private static let graceTenths = 30
    private static let watchNanos: UInt64 = 300_000_000

    init(python: String, logPath: String) {
        self.python = python
        self.logPath = logPath
    }

    /// Start (or restart) the chat service with these arguments.
    func run(arguments: [String]) {
        stopProcess()
        wanted = true
        restarts = 0
        generation += 1
        launch(arguments, generation)
    }

    func stop() {
        wanted = false
        generation += 1
        stopProcess()
    }

    private func launch(_ arguments: [String], _ mine: Int) {
        guard let child = spawn([python] + arguments) else { return retry(arguments, mine) }
        pid = child
        watch(arguments, mine)
    }

    /// Looks every moment whether the child is still there; if not, starts it again after a growing pause.
    private func watch(_ arguments: [String], _ mine: Int) {
        Task {
            while await self.isCurrent(mine) {
                try? await Task.sleep(nanoseconds: Self.watchNanos)
                guard await self.reapIfGone(mine) else { continue }
                return await self.retry(arguments, mine)
            }
        }
    }

    private func isCurrent(_ mine: Int) -> Bool { mine == generation && wanted }

    private func reapIfGone(_ mine: Int) -> Bool {
        guard mine == generation, pid > 0 else { return false }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return false }
        pid = 0
        return true
    }

    private func retry(_ arguments: [String], _ mine: Int) {
        restarts += 1
        let delay = min(Self.longestDelay, Self.firstDelay << UInt64(min(restarts, 4)))
        Task {
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            await self.relaunch(arguments, mine)
        }
    }

    private func relaunch(_ arguments: [String], _ mine: Int) {
        guard isCurrent(mine), pid == 0 else { return }
        launch(arguments, mine)
    }

    private func stopProcess() {
        guard pid > 0 else { return }
        let child = pid
        pid = 0
        kill(-child, SIGTERM)
        var status: Int32 = 0
        for _ in 0..<Self.graceTenths {
            if waitpid(child, &status, WNOHANG) == child { return }
            usleep(100_000)
        }
        kill(-child, SIGKILL)
        waitpid(child, &status, 0)
    }

    private func spawn(_ arguments: [String]) -> pid_t? {
        trimLog()
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var everySignal = sigset_t(), none = sigset_t()
        sigfillset(&everySignal)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        posix_spawnattr_setsigmask(&attributes, &none)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETPGROUP))
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var child: pid_t = 0
        return posix_spawn(&child, python, &actions, &attributes, argv, environ) == 0 ? child : nil
    }

    private func trimLog() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: logPath)[.size]) as? Int, size > Self.maxLogBytes else { return }
        try? FileManager.default.removeItem(atPath: logPath)
    }
}
