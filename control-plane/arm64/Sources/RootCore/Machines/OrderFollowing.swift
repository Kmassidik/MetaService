import Foundation

/// How long the parent follows an order it gave a helper before it calls it lost. A create is the slowest: the helper may pull the image first, and it only calls the VM
/// made after the VM has answered (it waits up to `helperStartSeconds` for the first try with systemd and as long again for the second try without it).
public enum OrderFollowing {
    public static let pollSeconds = 1
    public static let giveUpAfterSeconds = 30 * 60
    public static let lostContactAfterPolls = 300

    /// What the macOS helper may spend on one create, in seconds: its longest tool call (the image pull), then two tries to start the VM, each with the wait for an answer
    /// (60) and the settle time (3), and the removal of the first VM in between.
    static let helperImagePullSeconds = 900
    static let helperStartSeconds = 60 + 3
    static let helperTries = 2

    /// The most a create can take a helper, plus a little room.
    public static var longestCreateSeconds: Int { helperImagePullSeconds + helperTries * helperStartSeconds + 60 }
}
