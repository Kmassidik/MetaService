import Foundation

/// The root part of "Install it for me" for full VMs: qemu and the UEFI firmware it boots with, then the KVM module, because a computer with no `/dev/kvm` usually has the
/// module built but not loaded. Everything is fixed text; the only thing read from the computer is its own CPU type, which decides the package names.
///
/// Debian and Ubuntu name the package after the machine it emulates: `qemu-system-x86` (it holds `qemu-system-x86_64`) with the firmware in `ovmf` on x86, and
/// `qemu-system-arm` (it holds `qemu-system-aarch64`) with the arm64 firmware in `qemu-efi-aarch64` on ARM.
///
/// `qemu-utils` is not optional: Incus runs `qemu-img` on an image before it can start a VM from it, and a machine with only
/// `qemu-system-*` fails with `Failed to find executable "qemu-img"` (seen on the RTX 5090, 2026-10-26).
enum VmPackagesScript {
    static let body = """
    case "$(uname -m)" in
      x86_64|amd64) packages='qemu-system-x86 ovmf qemu-utils' ;;
      aarch64|arm64) packages='qemu-system-arm qemu-efi-aarch64 qemu-utils' ;;
      *) fail 'this computer'"'"'s CPU type is not one qemu is installed for here' ;;
    esac
    aptget install --no-install-recommends $packages || fail 'installing qemu did not work'
    command -v qemu-system-x86_64 >/dev/null 2>&1 || command -v qemu-system-aarch64 >/dev/null 2>&1 || fail 'qemu is still missing after the install'
    command -v qemu-img >/dev/null 2>&1 || fail 'qemu is installed, but qemu-img is still missing, so Incus cannot read a VM image'
    # Both modules are tried: the one for another maker fails with "not found", and that is fine.
    for module in kvm_amd kvm_intel; do
      modprobe "$module" >"$log" 2>&1 || true
    done
    [ -e /dev/kvm ] || fail 'qemu was installed, but /dev/kvm is still missing: the KVM module did not load, so virtualization may be turned off in the BIOS'
    echo '\(InstallMissingScripts.detailMarker) /dev/kvm is there now, so full VMs can run'

    """
}
