import Foundation

/// A line about a login that failed, for whoever runs the parent. It carries what ssh or the other computer said, which can hold a host name or a user name but never a password.
enum RemoteLog {
    static func say(_ line: String) {
        let flat = line.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        FileHandle.standardError.write(Data("metaservice-root: \(flat.prefix(400))\n".utf8))
    }
}
