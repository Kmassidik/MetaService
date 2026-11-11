import Foundation

public enum MachineState: String, Sendable {
    case online, busy, offline
}

public enum MachineStates {
    public static let heartbeatSeconds = 15
    public static let missedBeforeOffline = 3
    public static let observationSeconds = 45
    private static let busyWorkloadStates: Set<String> = ["provisioning", "deleting"]

    /// offline after 3 missed heartbeats; busy while any workload is being created or deleted.
    public static func derive(lastSeen: Date?, now: Date, workloadStates: [String]) -> MachineState {
        guard let lastSeen else { return .offline }
        let silence = now.timeIntervalSince(lastSeen)
        guard silence <= Double(heartbeatSeconds * missedBeforeOffline) else { return .offline }
        return workloadStates.contains(where: busyWorkloadStates.contains) ? .busy : .online
    }

    /// A restart hides a stale offline answer only while this process waits for its first current heartbeat.
    public static func statePending(lastSeen: Date?, now: Date, observingSince: Date, state: MachineState) -> Bool {
        guard state == .offline else { return false }
        guard now < observingSince.addingTimeInterval(Double(observationSeconds)) else { return false }
        guard let lastSeen else { return true }
        return lastSeen < observingSince
    }
}
