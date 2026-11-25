import Foundation

/// The fixes the panel can run for a warning in the security look ("Turn on the firewall for me", "Turn off password login for me"):
/// one offer per warning that has a fix and a login that may use sudo.
/// Password login is offered ONLY when the machine answered `has_key_login=yes`: without a key that fix locks the owner out,
/// and the script re-checks the keys itself at apply time (the panel's answer can be stale).
public enum SecurityFixes {
    public static func offers(security: RemoteSecurity?, facts: RemoteFacts) -> [InstallOffer] {
        guard let security else { return [] }
        var offers: [InstallOffer] = []
        if security.firewall == false, let offer = InstallOffers.offer(for: .firewall, facts: facts) { offers.append(offer) }
        if security.passwordLogin == true, security.hasKeyLogin == true, let offer = InstallOffers.offer(for: .passwordLogin, facts: facts) { offers.append(offer) }
        return offers
    }
}
