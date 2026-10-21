import Foundation

/// The root part of "Install it for me" for NVIDIA's container toolkit on Debian and Ubuntu. These are the steps of NVIDIA's own install guide
/// (https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html): NVIDIA's package source and signing key, then the package.
/// It adds a third-party package source, which the panel says before the button is pressed. Docker, containerd and the like are not configured: Incus needs none of that.
enum GpuToolkitScript {
    static let keyURL = "https://nvidia.github.io/libnvidia-container/gpgkey"
    static let listURL = "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list"
    static let keyring = "/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    static let sourceFile = "/etc/apt/sources.list.d/nvidia-container-toolkit.list"

    static let body = """
    aptget install --no-install-recommends ca-certificates curl gnupg2 || fail 'the tools that fetch NVIDIA'"'"'s package source could not be installed'
    raw=$(mktemp) && out=$(mktemp) || fail 'could not make a temporary file'
    curl -fsSL \(keyURL) -o "$raw" >"$log" 2>&1 || { rm -f "$raw" "$out"; fail 'NVIDIA'"'"'s signing key could not be downloaded'; }
    gpg --dearmor --yes -o \(keyring) "$raw" >"$log" 2>&1 || { rm -f "$raw" "$out"; fail 'NVIDIA'"'"'s signing key could not be read'; }
    curl -fsSL \(listURL) -o "$raw" >"$log" 2>&1 || { rm -f "$raw" "$out"; fail 'NVIDIA'"'"'s package list could not be downloaded'; }
    sed 's#deb https://#deb [signed-by=\(keyring)] https://#g' "$raw" >"$out" && install -m 0644 "$out" \(sourceFile) || { rm -f "$raw" "$out"; fail 'NVIDIA'"'"'s package source could not be added'; }
    rm -f "$raw" "$out"
    aptget update || fail 'the package list could not be updated after adding NVIDIA'"'"'s package source'
    aptget install nvidia-container-toolkit || fail 'installing nvidia-container-toolkit did not work'
    command -v nvidia-ctk >/dev/null 2>&1 || fail 'the NVIDIA container toolkit is still missing after the install'

    """
}
