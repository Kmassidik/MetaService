import Foundation
import RootCore
import RootStore

/// Keeps the job tables tidy: finished jobs and notifications older than 30 days go, once at start and then every few hours.
final class JobMaintenance: Sendable {
    private let commands: CommandStore
    private let notifications: NotificationStore
    private let clock: Clock

    static let everySeconds: UInt64 = 6 * 3_600
    static let keepDays = 30
    private static let secondsPerDay: TimeInterval = 86_400

    init(commands: CommandStore, notifications: NotificationStore, clock: Clock) {
        self.commands = commands
        self.notifications = notifications
        self.clock = clock
    }

    func start() {
        Task.detached { [self] in
            while true {
                prune()
                try? await Task.sleep(nanoseconds: Self.everySeconds * 1_000_000_000)
            }
        }
    }

    private func prune() {
        let now = clock.now
        let cutoff = now.addingTimeInterval(-TimeInterval(Self.keepDays) * Self.secondsPerDay)
        do {
            _ = try commands.pruneFinished(before: cutoff)
            _ = try notifications.prune(now: now)
        } catch {
            FileHandle.standardError.write(Data("metaservice-root: job cleanup failed: \(error)\n".utf8))
        }
    }
}
