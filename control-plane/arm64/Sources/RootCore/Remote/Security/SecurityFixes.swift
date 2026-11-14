import Foundation

/// The fixes the panel can run for a warning in the security look ("Turn on the firewall for me"): one offer per warning that has a fix and a login that may use sudo.
public enum SecurityFixes {
    public static func offers(security: RemoteSecurity?, facts: RemoteFacts) -> [InstallOffer] {
        guard let security, security.firewall == false else { return [] }
        return [InstallOffers.offer(for: .firewall, facts: facts)].compactMap { $0 }
    }
}
