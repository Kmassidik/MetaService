import Foundation
import MSCore

/// The optional `processes` query of `GET /v1/stats`: `1` or absent lists the top programs, `0` skips the scan (the expensive part) and answers with an empty list.
public enum StatsRequest {
    public static let parameter = "processes"

    /// `values` are all the `processes` parameters of the request, in order. Anything but one `1` or one `0` is an input error.
    public static func includesProcesses(values: [String]) throws -> Bool {
        guard !values.isEmpty else { return true }
        guard values.count == 1, let only = values.first else { throw InputError("processes must be 1 or 0") }
        switch only {
        case "1": return true
        case "0": return false
        default: throw InputError("processes must be 1 or 0")
        }
    }
}
