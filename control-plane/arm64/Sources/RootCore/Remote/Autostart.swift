import Foundation

/// The "Starts at boot" row, for a computer that already has MetaService's box on it: whether that computer's helper is registered with the system's own boot
/// service, so it comes back by itself after a restart. Without the registration the machine is offline after a power cycle until somebody runs
/// `~/metaservice-box/start.sh`, which is exactly what was seen on 2026-10-26: a green parent with grey machines.
///
/// The row warns, it never stops anything: a computer without the registration works, and only comes back offline after a restart. A computer that is not ours
/// is never asked, so there is no row and no offer there.
///
/// It is a cross and not a tick when the registration is missing, because a green tick would claim the opposite of the sentence; it is in `optionalRows`, so
/// it never stops a computer from being added, and the panel draws it as the same amber warning as a missing "Can run workloads".
enum Autostart {
    static let rowId = "autostart"
    static let label = "Starts at boot"
    static let registeredDetail = "Registered: this computer's helper starts again by itself after a restart."
    static let missingDetail = "This computer's helper is not registered to start at boot, so it shows offline after a restart."

    /// Nil when the check did not answer, which it only does for a computer that has no box of ours: nothing to say, so no row.
    static func requirement(_ facts: RemoteFacts) -> Requirement? {
        guard let registered = facts.autostart else { return nil }
        guard registered else {
            return Requirement(id: rowId, label: label, ok: false, detail: missingDetail, fix: ManualFixes.autostart(facts),
                               install: InstallOffers.offer(for: .autostart, facts: facts))
        }
        return Requirement(id: rowId, label: label, ok: true, detail: registeredDetail)
    }
}
