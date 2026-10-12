import Foundation

/// The host keys the parent trusts, one line each, in the known_hosts file that ssh reads. A key is added only after the operator confirmed its fingerprint,
/// and a key that is there is never replaced: a different key for the same host is a refusal, not an update.
struct HostKeyPins {
    enum Status { case new, same, changed }

    let path: String

    static func spec(of line: String) -> String? { line.split(separator: " ").first.map(String.init) }

    func status(of line: String) -> Status {
        guard let spec = Self.spec(of: line) else { return .changed }
        let pinned = lines().filter { Self.spec(of: $0) == spec }
        guard !pinned.isEmpty else { return .new }
        return pinned.contains(line) ? .same : .changed
    }

    func pin(_ line: String) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard FileManager.default.fileExists(atPath: path) else {
            FileManager.default.createFile(atPath: path, contents: Data((line + "\n").utf8), attributes: [.posixPermissions: 0o600])
            return
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line + "\n").utf8))
    }

    /// A machine was removed: its pin goes too, so the same address can be added again later with whatever key it has then.
    func forget(spec: String) throws {
        let kept = lines().filter { Self.spec(of: $0) != spec }
        try Data((kept.map { $0 + "\n" }.joined()).utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func lines() -> [String] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

/// Turns a host name into an IPv4 address, so the "private network only" rule is checked on what the name really points to.
enum HostResolver {
    static func ipv4(_ host: String) -> String? {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var found: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &found) == 0, let first = found else { return nil }
        defer { freeaddrinfo(found) }
        guard let address = first.pointee.ai_addr else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        guard inet_ntop(AF_INET, &value, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }
}
