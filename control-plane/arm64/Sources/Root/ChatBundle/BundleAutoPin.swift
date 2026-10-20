import Foundation
import RootCore
import RootStore

/// With nothing pinned and one chat built, the parent pins that one itself, so turning Ruvio on needs no extra step. It says so in the audit log.
struct BundleAutoPin {
    static let actor = "root"
    let bundles: BundleStore
    let audit: AuditStore
    let clock: Clock

    func run() throws {
        guard let version = try bundles.pinTheOnlyBuiltVersion(actor: Self.actor, now: clock.now) else { return }
        try audit.record(actor: Self.actor, action: "bundle.autopin", target: version, at: clock.now)
    }
}
