import Foundation

/// How an Agent on another computer reaches the parent: through the SSH connection the parent itself opened to that computer (a reverse tunnel). On that computer the parent
/// is simply `127.0.0.1:<port>`, so the parent never has to listen on the network and nothing about its own address has to be set or kept.
public enum ParentUrl {
    public static func make(port: Int) -> String { "http://127.0.0.1:\(port)" }

    private static let loopback = "127.0.0.1"

    /// Whether the target is the computer the parent runs on: by its loopback, or by one of its own network addresses.
    public static func isThisComputer(_ target: String, ownAddresses: [String] = []) -> Bool { IPv4.isLoopback(target) || ownAddresses.contains(target) }

    /// The port to open on that computer's loopback for the return path, or nil when that computer is this one (the parent is already on its loopback).
    public static func reversePort(listenPort: Int, target: String, ownAddresses: [String] = []) -> Int? { isThisComputer(target, ownAddresses: ownAddresses) ? nil : listenPort }

    /// The address an Agent's first call comes from, when it is known in advance: on this computer it is always loopback, whichever address the computer was added by.
    public static func arrivalAddress(target: String, ownAddresses: [String] = []) -> String? { isThisComputer(target, ownAddresses: ownAddresses) ? loopback : nil }
}
