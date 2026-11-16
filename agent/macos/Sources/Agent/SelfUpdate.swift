import CryptoKit
import Darwin
import Foundation
import Hummingbird
import AgentCore

/// "Update helper" for a Mac that joined through Share a PC: the panel has no SSH login on it, so the helper replaces itself. It downloads the build the parent offers (over the same
/// tunnel, with the machine token it reports with), checks the SHA-256 against the build the panel asked for, writes it next to itself, and a small script outside this program's
/// session swaps the file and restarts the LaunchAgent (bootout, then bootstrap: on macOS 27 a replaced build must never be kickstarted). The old file is put back if the new helper
/// does not come up. Nothing here uses sudo.
struct SelfUpdate {
    enum Outcome: Equatable {
        case started, current, notJoined
        case failed(String)
    }

    static let maxBytes = 64 * 1024 * 1024
    static let settleSeconds = 25
    /// The first bytes of a 64-bit Mach-O program.
    static let machOMagic: [UInt8] = [0xcf, 0xfa, 0xed, 0xfe]
    static let downloadSeconds: TimeInterval = 120

    let stateDirectory: String
    let root: URL?
    let machineToken: String?
    /// The running program's file and build.
    let ownPath: String
    let currentBuild: String?

    static func validBuild(_ text: String) -> Bool {
        (8...64).contains(text.utf8.count) && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    static func validLabel(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5a) || ($0 >= 0x61 && $0 <= 0x7a) || $0 == 0x2e || $0 == 0x2d || $0 == 0x5f }
    }

    static func verified(_ data: Data, wanted: String) -> String? {
        guard Array(data.prefix(4)) == machOMagic else { return "the downloaded file is not a Mac program" }
        let seen = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return seen.hasPrefix(wanted) ? nil : "the downloaded helper is not the build the panel asked for, so it was not installed"
    }

    /// `joined.env` values, only the ones this needs. The join script writes every value shell-quoted
    /// (`shq`) because `leave.sh` sources the file, so surrounding single quotes are stripped here.
    static func joinSettings(_ text: String) -> [String: String] {
        var found: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            if ["MS_LABEL", "MS_UNIT", "MS_UID"].contains(key) {
                var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                if value.count >= 2, value.first == "'", value.last == "'" { value = String(value.dropFirst().dropLast()) }
                found[key] = value
            }
        }
        return found
    }

    func run(wanted: String) async -> Outcome {
        let home = (stateDirectory as NSString).deletingLastPathComponent
        guard let text = try? String(contentsOfFile: home + "/joined.env", encoding: .utf8) else { return .notJoined }
        let settings = Self.joinSettings(text)
        guard let label = settings["MS_LABEL"], Self.validLabel(label), let plist = settings["MS_UNIT"], !plist.isEmpty, let uid = settings["MS_UID"], uid.allSatisfy(\.isNumber) else { return .notJoined }
        if currentBuild?.hasPrefix(wanted) == true { return .current }
        guard let root, let machineToken else { return .failed("this helper has no parent to download from") }
        var request = URLRequest(url: root.appendingPathComponent("v1/agents/build"))
        request.setValue("Bearer \(machineToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.downloadSeconds
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 else { return .failed("the parent did not give the new helper") }
        guard data.count <= Self.maxBytes else { return .failed("the new helper is too large") }
        if let why = Self.verified(data, wanted: wanted) { return .failed(why) }
        let fresh = ownPath + ".new"
        do {
            try data.write(to: URL(fileURLWithPath: fresh))
            chmod(fresh, 0o755)
        } catch {
            return .failed("the new helper could not be written next to the old one")
        }
        guard Self.startSwap(fresh: fresh, own: ownPath, label: label, plist: plist, uid: uid) else {
            try? FileManager.default.removeItem(atPath: fresh)
            return .failed("the swap could not be started")
        }
        return .started
    }

    /// The script runs in its own session (POSIX_SPAWN_SETSID), so booting out this helper's LaunchAgent does not take the swap down with it.
    static func startSwap(fresh: String, own: String, label: String, plist: String, uid: String) -> Bool {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        let arguments = ["sh", "-c", SwapScript.text, "swap", fresh, own, label, plist, uid, String(settleSeconds)]
        var cStrings: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, "/bin/sh", nil, &attributes, cStrings, environ) == 0
    }
}

enum SwapScript {
    static let text = #"""
    # Usage: swap <new file> <installed file> <label> <plist> <uid> <settle seconds>
    NEW=$1; OWN=$2; LABEL=$3; PLIST=$4; USER_ID=$5; SETTLE=${6:-25}
    OLD="$OWN.old"
    sleep 2
    cp -f "$OWN" "$OLD" 2>/dev/null || exit 1
    mv -f "$NEW" "$OWN" || exit 1
    launchctl bootout "gui/$USER_ID/$LABEL"
    launchctl bootstrap "gui/$USER_ID" "$PLIST"
    sleep "$SETTLE"
    if launchctl print "gui/$USER_ID/$LABEL" 2>/dev/null | grep -q "state = running"; then rm -f "$OLD"; exit 0; fi
    launchctl bootout "gui/$USER_ID/$LABEL"
    mv -f "$OLD" "$OWN"
    launchctl bootstrap "gui/$USER_ID" "$PLIST"
    exit 1
    """#
}

struct SelfUpdateRoutes {
    let update: SelfUpdate

    func register(on router: Router<AgentContext>) {
        router.post("/v1/update") { request, _ in
            let body = try await AgentRoutes.body(request)
            let wanted = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["build"] as? String ?? ""
            guard SelfUpdate.validBuild(wanted) else { return Json.error(.badRequest, "invalid_input", "the build is not acceptable") }
            switch await update.run(wanted: wanted) {
            case .started: return try Json.response(["started": true])
            case .current: return try Json.response(["started": false, "current": true])
            case .notJoined: return Json.error(.notFound, "not_joined", "this computer did not join through the join script, so it is updated over SSH")
            case .failed(let why): return Json.error(.conflict, "update_failed", why)
            }
        }
    }
}
