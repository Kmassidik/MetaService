import Foundation

public enum MachineState: String, Sendable {
    case online, busy, offline
}

public enum MachineStates {
    public static let heartbeatSeconds = 15
    public static let missedBeforeOffline = 3
    private static let busyWorkloadStates: Set<String> = ["provisioning", "deleting"]

    /// offline after 3 missed heartbeats; busy while any workload is being created or deleted.
    public static func derive(lastSeen: Date?, now: Date, workloadStates: [String]) -> MachineState {
        guard let lastSeen else { return .offline }
        let silence = now.timeIntervalSince(lastSeen)
        guard silence <= Double(heartbeatSeconds * missedBeforeOffline) else { return .offline }
        return workloadStates.contains(where: busyWorkloadStates.contains) ? .busy : .online
    }
}
