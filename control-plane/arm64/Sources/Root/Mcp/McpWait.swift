import Foundation
import RootCore
import RootStore

/// Waiting for a request to come true, using the command and VM state the parent already keeps. The AI is never kept longer than it asked.
extension McpService {
    static let pollNanoseconds: UInt64 = 300_000_000

    /// Polls until `ready` says yes (then the request as `get_request` shows it), the request fails (thrown as the plain reason), or the seconds run out
    /// (then `{"status": pendingWord, "request_id"}` so the AI can poll with get_request).
    func waitFor(_ requestId: String, token: McpTokenRecord, seconds: Int, pendingWord: String,
                 ready: (McpRequestRow, WorkloadSummary?) -> Bool) async throws -> [String: Any] {
        let deadline = clock.now.addingTimeInterval(TimeInterval(seconds))
        while true {
            settle(token)
            guard let request = try requests.get(id: requestId) else { throw McpRefusal.noRequest }
            if request.state == .failed { throw McpRefusal(kind: "failed", message: request.result?["message"] as? String ?? "it did not work") }
            if request.state == .done && ready(request, currentVm(request, token: token)) { return requestView(request, token: token) }
            guard clock.now < deadline else { return ["status": pendingWord, "request_id": requestId, "message": "Still in progress: call get_request with this request_id in a few seconds."] }
            try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
        }
    }

    /// The VM a request is about, as its machine lists it now.
    private func currentVm(_ request: McpRequestRow, token: McpTokenRecord) -> WorkloadSummary? {
        let row: McpWorkloadRow?
        if request.kind == .create {
            row = try? ownership.row(request: request.id)
        } else {
            row = try? ownership.find(token: token.id, machine: request.params["machine"] as? String ?? "", workload: request.params["vm"] as? String ?? "")
        }
        return row.flatMap(liveVm)?.vm
    }
}
