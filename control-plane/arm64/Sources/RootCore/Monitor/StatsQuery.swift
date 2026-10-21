import Foundation

/// The optional `processes` query of the stats route: `1` (or absent) includes the top programs, `0` leaves them out and spares the helper the scan.
/// Nothing the caller typed is ever passed on to a helper: the helper is asked with one of two fixed paths.
public enum StatsQuery {
    public struct Refused: Error, Equatable, Sendable {
        public let message = "processes must be 1 or 0"
    }

    public static let parameter = "processes"

    private static let withProcessesPath = "/v1/stats"
    private static let withoutProcessesPath = "/v1/stats?processes=0"

    /// `values` are all the `processes` parameters of the request, in order.
    public static func wantsProcesses(values: [String]) throws -> Bool {
        guard !values.isEmpty else { return true }
        guard values.count == 1, let only = values.first else { throw Refused() }
        switch only {
        case "1": return true
        case "0": return false
        default: throw Refused()
        }
    }

    public static func helperPath(processes: Bool) -> String {
        processes ? withProcessesPath : withoutProcessesPath
    }
}

extension MachineStats {
    /// The same reading without the process list (a held reading that has one can answer a request that does not want it).
    public func withoutProcesses() -> MachineStats {
        var copy = self
        copy.processes = []
        return copy
    }
}
