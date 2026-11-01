import Foundation
import RootCore

/// Add machine, Verify: the security look at the other computer. It never fails the check: when the look cannot be made (a timeout, a refused command, an answer that
/// is not facts) every field is simply unknown, and the Verify reply is the same as it was.
enum RemoteSecurityRead {
    static func run(_ ssh: RemoteSsh, _ target: RemoteTarget, _ credentials: SshCredentials, facts: RemoteFacts) async -> RemoteSecurity? {
        guard facts.isMac || facts.isLinux else { return nil }
        do {
            let result = try await ssh.run(SecurityVerifyScript.script, on: target, with: credentials, timeout: SecurityVerifyScript.totalSeconds)
            guard result.status == 0 else {
                RemoteLog.say("the security look at \(target.host) ended with status \(result.status): \(result.errors.prefix(200))")
                return RemoteSecurity()
            }
            return RemoteSecurityParse.parse(result.output)
        } catch {
            RemoteLog.say("the security look at \(target.host) could not be made: \(error)")
            return RemoteSecurity()
        }
    }
}
