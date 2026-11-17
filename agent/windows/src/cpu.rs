//! The processors a workload can be given, as in Proxmox's Processors window: sockets, a CPU model and flags for a VM, a hard cap on CPU time for a
//! container. What this machine offers comes from the engine (the QEMU version VMs run on, whether `limits.cpu` takes a topology) and from
//! /proc/cpuinfo (who made the CPU). A create that asks for more than that is refused in plain words.
use crate::models::Capabilities;
use crate::validate::CreateRequest;
use serde::Serialize;

/// The machine's own CPU, which is what every VM got before. Always offered, always first.
pub const HOST_MODEL: &str = "host";
const X86_64: &str = "x86_64";
const CPUINFO: &str = "/proc/cpuinfo";

/// The CPU models a VM can be given besides `host`, each with the first QEMU release (major, minor) whose target/i386/cpu.c defines it.
/// Only unversioned names. A machine whose QEMU is older than a model's release is not offered that model.
const MODELS: [(&str, (u32, u32)); 12] = [
    ("EPYC", (2, 11)), ("EPYC-Rome", (5, 0)), ("EPYC-Milan", (6, 0)), ("EPYC-Genoa", (8, 1)),
    ("Skylake-Server", (2, 10)), ("Cascadelake-Server", (3, 1)), ("Icelake-Server", (3, 1)), ("SapphireRapids", (8, 0)),
    ("Haswell", (1, 3)), ("Broadwell", (2, 1)), ("kvm64", (0, 12)), ("qemu64", (0, 12)),
];

pub const NO_SOCKETS_MESSAGE: &str = "This machine cannot spread a VM's CPUs over more than one socket.";
pub const NO_MODEL_MESSAGE: &str = "This machine does not offer that CPU model for a VM.";
pub const NO_FLAG_MESSAGE: &str = "This machine cannot switch that CPU flag for a VM.";
pub const NO_LIMIT_MESSAGE: &str = "This machine cannot cap a container's CPU time.";

/// Who made the machine's CPU. It decides what nested-virt is: svm on AMD, vmx on Intel.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CpuVendor {
    Amd,
    Intel,
}

/// A CPU flag a VM can have switched on or off.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CpuFlag {
    NestedVirt,
    Aes,
}

impl CpuFlag {
    /// Every flag, in the order they are written down (nested-virt first).
    pub const ALL: [CpuFlag; 2] = [CpuFlag::NestedVirt, CpuFlag::Aes];

    /// The flag's name in the contract.
    pub fn name(self) -> &'static str {
        match self {
            CpuFlag::NestedVirt => "nested-virt",
            CpuFlag::Aes => "aes",
        }
    }
}

impl Serialize for CpuFlag {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.name())
    }
}

/// What a VM's processors can be given on this machine. `HOST_ONLY` is what every VM got before: the machine's own CPU, one socket, no flags.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CpuOffer {
    /// The QEMU version VMs run on, on an x86_64 machine whose engine says it. The CPU models beyond `host` follow from it.
    pub qemu: Option<(u32, u32)>,
    /// A VM can be spread over more than one socket.
    pub topology: bool,
    /// Who made the CPU of an x86_64 machine, when it is AMD or Intel. The flags are offered exactly then.
    pub vendor: Option<CpuVendor>,
}

impl CpuOffer {
    pub const HOST_ONLY: CpuOffer = CpuOffer { qemu: None, topology: false, vendor: None };

    /// What a machine of `arch` offers, from what its engine says (the QEMU version, sockets) and who made its CPU. Models beyond `host` and the flags
    /// are x86 words, so only x86_64 gets them.
    pub fn new(arch: &str, qemu: Option<(u32, u32)>, topology: bool, vendor: Option<CpuVendor>) -> CpuOffer {
        let x86 = arch == X86_64;
        CpuOffer { qemu: qemu.filter(|_| x86), topology, vendor: vendor.filter(|_| x86) }
    }

    /// The CPU models a VM can be given, `host` first.
    pub fn models(&self) -> Vec<&'static str> {
        let known = |release: (u32, u32)| self.qemu.is_some_and(|version| version >= release);
        std::iter::once(HOST_MODEL).chain(MODELS.iter().filter(|(_, release)| known(*release)).map(|(model, _)| *model)).collect()
    }

    /// The flags a VM can have switched on or off.
    pub fn flags(&self) -> &'static [CpuFlag] {
        if self.vendor.is_some() { &CpuFlag::ALL } else { &[] }
    }
}

/// Who made the CPU, from the `vendor_id` line of /proc/cpuinfo. Anything but AMD or Intel is None.
pub fn vendor_of(cpuinfo: &str) -> Option<CpuVendor> {
    let value = cpuinfo.lines().find_map(|line| line.split_once(':').filter(|(key, _)| key.trim() == "vendor_id").map(|(_, value)| value.trim()))?;
    match value {
        "AuthenticAMD" => Some(CpuVendor::Amd),
        "GenuineIntel" => Some(CpuVendor::Intel),
        _ => None,
    }
}

/// Who made this machine's CPU, read once at start. None when /proc/cpuinfo cannot be read or does not name AMD or Intel.
pub fn this_machines_vendor() -> Option<CpuVendor> {
    std::fs::read_to_string(CPUINFO).ok().and_then(|text| vendor_of(&text))
}

/// Why a create asks for processor settings this machine does not offer, in plain words. It is answered like a bad field (400), as the contract says.
/// None when everything asked for is offered. Sockets, even 1, need `cpu_topology`; `host` is always one of the models.
pub fn not_offered(request: &CreateRequest, capabilities: &Capabilities) -> Option<&'static str> {
    let offer = &capabilities.cpu;
    if request.cpu_sockets.is_some() && !offer.topology {
        return Some(NO_SOCKETS_MESSAGE);
    }
    if request.cpu_type.as_deref().is_some_and(|model| !offer.models().contains(&model)) {
        return Some(NO_MODEL_MESSAGE);
    }
    if request.cpu_flags.iter().any(|(flag, _)| !offer.flags().contains(flag)) {
        return Some(NO_FLAG_MESSAGE);
    }
    // `cpu_limit` follows `container` (see models.rs).
    if request.cpu_limit_percent.is_some() && !capabilities.container {
        return Some(NO_LIMIT_MESSAGE);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{GpuMode, Kind};

    const AMD_CPUINFO: &str = "processor\t: 0\nvendor_id\t: AuthenticAMD\ncpu family\t: 25\nmodel name\t: AMD Ryzen 9 7950X 16-Core Processor\nflags\t\t: fpu svm aes\n\nprocessor\t: 1\nvendor_id\t: AuthenticAMD\n";
    const INTEL_CPUINFO: &str = "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: Intel(R) Xeon(R) Gold 6338 CPU @ 2.00GHz\nflags\t\t: fpu vmx aes\n";
    const ARM_CPUINFO: &str = "processor\t: 0\nBogoMIPS\t: 2000.00\nFeatures\t: fp asimd aes\nCPU implementer\t: 0x41\nCPU part\t: 0xd4f\n";

    fn request(kind: Kind) -> CreateRequest {
        CreateRequest {
            command_id: "c".into(), name: "n".into(), kind, cpu: 4, ram_mb: 512, disk_gb: 1, gpu_mode: GpuMode::None, image: None, gpu_memory_gb: None,
            cpu_sockets: None, cpu_type: None, cpu_flags: Vec::new(), cpu_limit_percent: None,
        }
    }

    fn capabilities(cpu: CpuOffer) -> Capabilities {
        Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: false, cpu, sandbox: false }
    }

    const EVERYTHING: CpuOffer = CpuOffer { qemu: Some((9, 2)), topology: true, vendor: Some(CpuVendor::Amd) };

    #[test]
    fn host_comes_first_and_each_model_needs_its_qemu_release() {
        let on = |qemu| CpuOffer::new("x86_64", Some(qemu), false, None).models();
        assert_eq!(on((9, 2)), ["host", "EPYC", "EPYC-Rome", "EPYC-Milan", "EPYC-Genoa", "Skylake-Server", "Cascadelake-Server", "Icelake-Server", "SapphireRapids", "Haswell", "Broadwell", "kvm64", "qemu64"]);
        assert!(on((8, 1)).contains(&"EPYC-Genoa") && !on((8, 0)).contains(&"EPYC-Genoa"), "Genoa came with QEMU 8.1");
        assert!(on((8, 0)).contains(&"SapphireRapids") && !on((7, 2)).contains(&"SapphireRapids"), "Sapphire Rapids came with QEMU 8.0, not 7.1");
        assert!(on((6, 0)).contains(&"EPYC-Milan") && !on((5, 2)).contains(&"EPYC-Milan"));
        assert!(on((5, 0)).contains(&"EPYC-Rome") && !on((4, 2)).contains(&"EPYC-Rome"));
        assert!(on((2, 10)).contains(&"Skylake-Server") && !on((2, 9)).contains(&"Skylake-Server"));
        assert_eq!(on((10, 0)).len(), on((9, 2)).len(), "a newer QEMU keeps every model");
    }

    #[test]
    fn without_a_qemu_version_or_off_x86_only_host_is_offered() {
        assert_eq!(CpuOffer::new("x86_64", None, true, Some(CpuVendor::Intel)).models(), ["host"]);
        assert_eq!(CpuOffer::HOST_ONLY.models(), ["host"]);
        let arm = CpuOffer::new("aarch64", Some((9, 2)), true, Some(CpuVendor::Amd));
        assert_eq!((arm.models(), arm.flags(), arm.topology), (vec!["host"], &[][..], true), "sockets are not an x86 word");
    }

    #[test]
    fn the_flags_are_offered_only_on_an_amd_or_intel_x86_machine() {
        assert_eq!(CpuOffer::new("x86_64", None, false, Some(CpuVendor::Amd)).flags(), CpuFlag::ALL);
        assert_eq!(CpuOffer::new("x86_64", None, false, Some(CpuVendor::Intel)).flags(), CpuFlag::ALL);
        assert!(CpuOffer::new("x86_64", Some((9, 2)), true, None).flags().is_empty());
        assert_eq!(serde_json::to_value(CpuFlag::ALL).unwrap(), serde_json::json!(["nested-virt", "aes"]));
    }

    #[test]
    fn the_vendor_is_read_from_the_vendor_id_line() {
        assert_eq!(vendor_of(AMD_CPUINFO), Some(CpuVendor::Amd));
        assert_eq!(vendor_of(INTEL_CPUINFO), Some(CpuVendor::Intel));
        for other in [ARM_CPUINFO, "vendor_id\t: HygonGenuine\n", "vendor_id\t: CentaurHauls\n", "", "vendor_id", "my_vendor_id: AuthenticAMD\n", "\0\0"] {
            assert_eq!(vendor_of(other), None, "{other:?}");
        }
    }

    #[test]
    fn what_is_offered_is_accepted() {
        let vm = CreateRequest { cpu_sockets: Some(2), cpu_type: Some("EPYC-Genoa".into()), cpu_flags: vec![(CpuFlag::NestedVirt, true), (CpuFlag::Aes, false)], ..request(Kind::Vm) };
        assert_eq!(not_offered(&vm, &capabilities(EVERYTHING)), None);
        let container = CreateRequest { cpu_limit_percent: Some(150), ..request(Kind::Container) };
        assert_eq!(not_offered(&container, &capabilities(CpuOffer::HOST_ONLY)), None, "every container can be capped");
        assert_eq!(not_offered(&request(Kind::Vm), &capabilities(CpuOffer::HOST_ONLY)), None, "asking for nothing new always works");
        let host = CreateRequest { cpu_type: Some("host".into()), ..request(Kind::Vm) };
        assert_eq!(not_offered(&host, &capabilities(CpuOffer::HOST_ONLY)), None, "host is always one of the models");
        let one = CreateRequest { cpu_sockets: Some(1), ..request(Kind::Vm) };
        assert_eq!(not_offered(&one, &capabilities(EVERYTHING)), None);
    }

    #[test]
    fn each_setting_the_machine_does_not_offer_is_refused_by_name() {
        let without = |change: fn(&mut CpuOffer)| { let mut offer = EVERYTHING; change(&mut offer); capabilities(offer) };
        for count in [1, 2] {
            let sockets = CreateRequest { cpu_sockets: Some(count), ..request(Kind::Vm) };
            assert_eq!(not_offered(&sockets, &without(|offer| offer.topology = false)), Some(NO_SOCKETS_MESSAGE), "{count}: the field itself needs cpu_topology");
        }
        let genoa = CreateRequest { cpu_type: Some("EPYC-Genoa".into()), ..request(Kind::Vm) };
        assert_eq!(not_offered(&genoa, &without(|offer| offer.qemu = Some((8, 0)))), Some(NO_MODEL_MESSAGE));
        let unknown = CreateRequest { cpu_type: Some("No-Such-CPU".into()), ..request(Kind::Vm) };
        assert_eq!(not_offered(&unknown, &capabilities(EVERYTHING)), Some(NO_MODEL_MESSAGE));
        for flag in CpuFlag::ALL {
            let flagged = CreateRequest { cpu_flags: vec![(flag, false)], ..request(Kind::Vm) };
            assert_eq!(not_offered(&flagged, &without(|offer| offer.vendor = None)), Some(NO_FLAG_MESSAGE), "{flag:?}");
        }
        let capped = CreateRequest { cpu_limit_percent: Some(150), ..request(Kind::Container) };
        assert_eq!(not_offered(&capped, &Capabilities { container: false, ..capabilities(EVERYTHING) }), Some(NO_LIMIT_MESSAGE));
        for message in [NO_SOCKETS_MESSAGE, NO_MODEL_MESSAGE, NO_FLAG_MESSAGE, NO_LIMIT_MESSAGE] {
            assert!(!message.to_lowercase().contains("incus") && !message.contains("qemu"), "{message}");
        }
    }
}
