import Foundation

/// Installs Apple's `container` tool on a Mac from Apple's signed installer package, as ONE command run as root through sudo (see `InstallMissingScripts.sudoCommand`).
/// The package is fetched from Apple's GitHub release, its signature is checked before anything is installed, and it is removed afterwards. Nothing else on the Mac changes.
public enum AppleContainerScript {
    public static let version = "1.7.1"
    public static let packageURL = "https://github.com/apple/container/releases/download/\(version)/container-\(version)-installer-signed.pkg"
    /// The installer must be signed by Apple (a Developer ID Installer certificate of Apple Inc.); any other signer is refused.
    static let signer = "Developer ID Installer: Apple Inc."
    static let tool = "/usr/local/bin/container"

    /// Apple's tool needs Apple Silicon.
    public static func supports(_ facts: RemoteFacts) -> Bool { facts.isMac && ["arm64", "aarch64"].contains(facts.arch) }

    /// The helper picks its engine when it starts, so one already installed in the box is restarted as that user (best effort: the tool is installed either way).
    static func restartHelper(user: String, box: String) -> String {
        guard !user.isEmpty, RemoteInstallOptions.isPlainPath(box) else { return ":" }
        let quoted = Shell.quote(user), stop = Shell.quote(box + "/stop.sh"), start = Shell.quote(box + "/start.sh")
        return "[ -f \(start) ] && { sudo -u \(quoted) sh \(stop) >/dev/null 2>&1; sudo -u \(quoted) sh \(start) >/dev/null 2>&1; }; :"
    }

    public static func script(user: String = "", box: String = "") -> String {
        let ok = InstallMissingScripts.okMarker, done = InstallMissingScripts.doneMarker
        let error = InstallMissingScripts.errorMarker, detail = InstallMissingScripts.detailMarker
        return """
        echo \(ok)
        fail() { echo "\(error) $1"; [ -z "$log" ] || tail -n 3 "$log" | sed 's/^/\(detail) /'; exit 1; }
        log=$(mktemp) || fail 'could not make a temporary file'
        pkg=$(mktemp -d)/container.pkg || fail 'could not make a temporary folder'
        trap 'rm -rf "$log" "$(dirname "$pkg")"' EXIT
        [ "$(id -u)" = 0 ] || fail 'sudo did not give administrator rights'
        curl -fsSL --max-time 600 -o "$pkg" '\(packageURL)' >"$log" 2>&1 || fail 'that computer could not download Apple'"'"'s container installer from github.com'
        pkgutil --check-signature "$pkg" >"$log" 2>&1 || fail 'the downloaded installer is not signed'
        grep -q '\(signer)' "$log" || fail 'the downloaded installer is not signed by Apple, so it was not installed'
        installer -pkg "$pkg" -target / >"$log" 2>&1 || fail 'installing Apple'"'"'s container tool did not work'
        [ -x \(tool) ] || fail 'the container tool is still missing after the install'
        \(restartHelper(user: user, box: box))
        echo \(done)

        """
    }
}
