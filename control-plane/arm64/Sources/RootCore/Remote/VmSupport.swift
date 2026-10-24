import Foundation

/// The "Can run workloads" row for a Linux computer. "There is no /dev/kvm" has several different causes and only one of them is the BIOS, so each cause gets its own
/// sentence: virtualization off in the BIOS, virtualization on but the KVM module not loaded, or a computer that could not say which. qemu is named on its own, because
/// Incus makes containers without it; it is only needed for full VMs.
///
/// The row is always a tick on Linux: containers work, so the computer can be added. What is missing is said, and the offer turns it into full VMs.
enum VmSupport {
    static let rowId = "vm_support"
    static let label = "Can run workloads"

    static let kvmThere = "/dev/kvm is there: VMs and containers."
    static let biosOff = "Containers only: virtualization is off in the BIOS."
    static let moduleNotLoaded = "Containers only: virtualization is on, but the KVM module is not loaded."
    static let noKvm = "Containers only: there is no /dev/kvm, so full VMs cannot run."
    static let unknownKvm = "Could not check /dev/kvm."
    static let noQemu = "qemu is not installed."

    static let amdModule = "kvm_amd"
    static let intelModule = "kvm_intel"

    /// Debian and Ubuntu name these by the emulated machine: `qemu-system-x86` and its UEFI firmware `ovmf` on x86, `qemu-system-arm` (it holds `qemu-system-aarch64`)
    /// and `qemu-efi-aarch64` (the arm64 UEFI firmware) on ARM.
    static let x86Packages = "qemu-system-x86 ovmf"
    static let armPackages = "qemu-system-arm qemu-efi-aarch64"

    /// The row is a tick with something to do exactly when the part it can install is missing: no `/dev/kvm`, or no qemu. A fact the computer did not answer is never
    /// counted as missing, so a machine that could not say is never told it is broken.
    static func requirement(_ facts: RemoteFacts) -> Requirement {
        guard InstallOffers.needed(.vmPackages, facts) else { return Requirement(id: rowId, label: label, ok: true, detail: detail(facts)) }
        return Requirement(id: rowId, label: label, detail: detail(facts), stillWorthDoing: fix(facts), install: InstallOffers.offer(for: .vmPackages, facts: facts))
    }

    static func detail(_ facts: RemoteFacts) -> String {
        switch facts.kvm {
        case .some(true): return withQemu(kvmThere, facts)
        case .some(false): return withQemu(reasonWithoutKvm(facts), facts)
        case .none: return withQemu(unknownKvm, facts)
        }
    }

    private static func reasonWithoutKvm(_ facts: RemoteFacts) -> String {
        switch facts.virt {
        case .some(false): return biosOff
        case .some(true): return moduleNotLoaded
        case .none: return noKvm
        }
    }

    private static func withQemu(_ text: String, _ facts: RemoteFacts) -> String {
        facts.qemu == false ? "\(text) \(noQemu)" : text
    }

    /// What to do by hand. It always says the BIOS is off only when the computer said so; a computer that did not say is asked to check.
    static func fix(_ facts: RemoteFacts) -> String {
        let parts = [kvmFix(facts), facts.qemu == false ? ManualFixes.qemu(facts) : nil]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    private static func kvmFix(_ facts: RemoteFacts) -> String? {
        guard facts.kvm != true else { return nil }
        switch facts.virt {
        case .some(false): return "Turn virtualization on in that computer's BIOS or UEFI (SVM on an AMD chip, Intel VT on an Intel chip), then check again."
        case .some(true): return "Load the KVM module on that computer: \(loadCommand(facts)). Then check again."
        case .none: return "Check that virtualization is turned on in that computer's BIOS or UEFI (SVM on an AMD chip, Intel VT on an Intel chip), then load the KVM module: \(loadCommand(facts)). Then check again."
        }
    }

    /// The module name is only known when the chip says who made it; otherwise both are named, because loading the wrong one fails harmlessly ("not found").
    static func loadCommand(_ facts: RemoteFacts) -> String {
        switch cpuMaker(facts) {
        case .amd: return "`sudo modprobe \(amdModule)`"
        case .intel: return "`sudo modprobe \(intelModule)`"
        case .unknown: return "`sudo modprobe \(amdModule)` on an AMD chip or `sudo modprobe \(intelModule)` on an Intel chip"
        }
    }

    private enum CpuMaker { case amd, intel, unknown }

    private static func cpuMaker(_ facts: RemoteFacts) -> CpuMaker {
        let chip = facts.chip.lowercased()
        if chip.contains("amd") { return .amd }
        if chip.contains("intel") { return .intel }
        return .unknown
    }
}
