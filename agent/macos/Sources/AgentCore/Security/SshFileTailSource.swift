import Foundation

/// Tails `/var/log/sshd.log` (written by the metaservice sshd daemon with `-E`) and turns the
/// VERBOSE lines into events. The cursor is a byte offset persisted by the parent through the
/// route (`after`), so a restart resumes where reading stopped (spec I1, I5).
///
/// One connection yields one event: the first `Invalid user` / `Failed password` / preauth close
/// line for its `sshd-auth` process id wins (I3, I4); later lines of the same connection are
/// skipped. The `sshd -E` file has no per-line timestamps, so event time is the read time.
public struct SshFileTailSource {
    public let path: String

    public init(path: String = "/var/log/sshd.log") {
        self.path = path
    }

    /// The events from the bytes after `afterOffset`, up to the file's end, plus the offset to
    /// resume from. A shrunken file (rotation) restarts from zero with `reset`.
    public func events(afterOffset: Int, pidDedupe: inout [Int: String]) -> (events: [SecurityEvent], offset: Int, reset: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (events: [], offset: max(0, afterOffset), reset: false) }
        defer { try? handle.close() }
        let size = Int((try? handle.seekToEnd()) ?? 0)
        guard size > 0 else { return (events: [], offset: max(0, afterOffset), reset: false) }
        let rotated = afterOffset > size
        let start = rotated ? 0 : min(max(0, afterOffset), size)
        try? handle.seek(toOffset: UInt64(start))
        let data = handle.readDataToEndOfFile()
        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") {
            // The last line may still be half-written: drop it, the next read picks it up.
            if let cut = text.lastIndex(of: "\n") { text = String(text[...cut]) }
        }
        let seen = SshVerboseLog.parseClassicLines(text)
        var events: [SecurityEvent] = []
        let nowTime = SecurityLogTime.isoNow()
        for sighting in seen {
            let isNew = pidDedupe[sighting.pid].map { $0 != sighting.user } ?? true
            guard isNew else { continue }
            pidDedupe[sighting.pid] = sighting.user
            if sighting.failed {
                events.append(SecurityEvent(time: nowTime, type: .failedLogin, user: sighting.user, address: sighting.address, count: 1))
            } else {
                events.append(SecurityEvent(time: nowTime, type: .login, user: sighting.user, address: sighting.address, count: 1))
            }
        }
        let end = start + text.utf8.count
        return (events: events, offset: rotated ? end : min(end, Int(size)), reset: rotated)
    }
}
