import Foundation

/// How an Agent on another computer reaches the parent: through the SSH connection the parent itself opened to that computer (a reverse tunnel). On that computer the parent
/// is simply `127.0.0.1:<port>`, so the parent never has to listen on the network and nothing about its own address has to be set or kept.
public enum ParentUrl {
    public static func make(port: Int) -> String { "http://127.0.0.1:\(port)" }

    /// The port to open on that computer's loopback for the return path, or nil when that computer is this one (the parent is already on its loopback).
    public static func reversePort(listenPort: Int, target: String) -> Int? { IPv4.isLoopback(target) ? nil : listenPort }
}
