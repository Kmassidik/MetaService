//! How much of this machine MetaService may hand to workloads. All sizes are decided here, never read back from the OS.
use crate::models::{Capabilities, GpuMode, Kind, Refusal, Workload, State};
use crate::validate::CreateRequest;

#[derive(Clone, Debug, PartialEq)]
pub struct SpaceBudget {
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub ram_allowance_mb: Option<u64>,
    pub disk_allowance_gb: Option<u64>,
    pub reserve_ram_mb: u64,
    pub reserve_disk_gb: u64,
    pub margin_disk_gb: u64,
}

pub const DEFAULT_MARGIN_DISK_GB: u64 = 20;

impl SpaceBudget {
    pub fn new(ram_total_mb: u64, disk_total_gb: u64) -> Self {
        SpaceBudget {
            ram_total_mb,
            disk_total_gb,
            ram_allowance_mb: None,
            disk_allowance_gb: None,
            reserve_ram_mb: (ram_total_mb / 4).max(4096),
            reserve_disk_gb: (disk_total_gb / 5).max(30),
            margin_disk_gb: DEFAULT_MARGIN_DISK_GB,
        }
    }

    /// RAM left for new workloads: the allowance, minus the host's reserve, minus workloads that are running.
    pub fn free_ram_mb(&self, workloads: &[Workload]) -> u64 {
        let running: u64 = workloads.iter().filter(|w| matches!(w.state, State::Running | State::Provisioning)).map(|w| w.ram_mb).sum();
        self.ram_allowance_mb.unwrap_or(self.ram_total_mb).min(self.ram_total_mb).saturating_sub(self.reserve_ram_mb).saturating_sub(running)
    }

    /// Disk left: every workload keeps its disk whether it runs or not.
    pub fn free_disk_gb(&self, workloads: &[Workload]) -> u64 {
        let used: u64 = workloads.iter().map(|w| w.disk_gb).sum();
        self.disk_allowance_gb.unwrap_or(self.disk_total_gb).min(self.disk_total_gb).saturating_sub(self.reserve_disk_gb).saturating_sub(self.margin_disk_gb).saturating_sub(used)
    }

    /// Capability, RAM and disk checks. `os_available_disk_gb` is what the file system says is free; it can only make the answer stricter.
    pub fn check(&self, request: &CreateRequest, workloads: &[Workload], capabilities: &Capabilities, os_available_disk_gb: Option<u64>) -> Result<(), Refusal> {
        self.check_capability(request, capabilities)?;
        let ram = self.free_ram_mb(workloads);
        if request.ram_mb > ram {
            return Err(refusal("not_enough_room", "not enough RAM", "ram_mb", request.ram_mb, ram));
        }
        let disk = self.free_disk_gb(workloads);
        if request.disk_gb > disk {
            return Err(refusal("not_enough_room", "not enough disk", "disk_gb", request.disk_gb, disk));
        }
        match os_available_disk_gb {
            Some(real) if request.disk_gb + self.margin_disk_gb > real => {
                Err(refusal("not_enough_room", "the disk is fuller than the budget says", "disk_gb", request.disk_gb, real.saturating_sub(self.margin_disk_gb)))
            }
            _ => Ok(()),
        }
    }

    fn check_capability(&self, request: &CreateRequest, capabilities: &Capabilities) -> Result<(), Refusal> {
        let can_run = if request.kind == Kind::Vm { capabilities.vm } else { capabilities.container };
        if !can_run {
            return Err(refusal("missing_capability", &format!("this machine cannot run a {}", if request.kind == Kind::Vm { "vm" } else { "container" }), "capability", 1, 0));
        }
        let gpu_ok = match request.gpu_mode {
            GpuMode::None => true,
            GpuMode::Container => capabilities.gpu_in_container && request.kind == Kind::Container,
            GpuMode::Passthrough => capabilities.gpu_in_vm && request.kind == Kind::Vm,
        };
        if gpu_ok { Ok(()) } else { Err(refusal("missing_capability", "that gpu mode is not available here", "capability", 1, 0)) }
    }
}

fn refusal(code: &'static str, message: &str, resource: &'static str, needed: u64, free: u64) -> Refusal {
    Refusal { code, message: message.to_string(), resource, needed, free }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Workload;

    fn request(ram: u64, disk: u64, kind: Kind, gpu: GpuMode) -> CreateRequest {
        CreateRequest { command_id: "c".into(), name: "n".into(), kind, cpu: 1, ram_mb: ram, disk_gb: disk, gpu_mode: gpu, image: None }
    }

    fn workload(ram: u64, disk: u64, state: State) -> Workload {
        Workload { id: "w".into(), name: "n".into(), kind: Kind::Vm, state, cpu: 1, ram_mb: ram, disk_gb: disk, gpu_mode: GpuMode::None, address: None, bundle_version: None }
    }

    const ALL: Capabilities = Capabilities { vm: true, container: true, gpu_in_vm: false, gpu_in_container: true };

    fn budget() -> SpaceBudget {
        SpaceBudget { reserve_ram_mb: 8192, reserve_disk_gb: 100, margin_disk_gb: 20, ..SpaceBudget::new(32768, 1000) }
    }

    #[test]
    fn defaults_and_free_numbers() {
        assert_eq!((SpaceBudget::new(16384, 228).reserve_ram_mb, SpaceBudget::new(16384, 228).reserve_disk_gb), (4096, 45));
        let b = budget();
        assert_eq!((b.free_ram_mb(&[]), b.free_disk_gb(&[])), (24576, 880));
        let busy = [workload(4096, 50, State::Running), workload(2048, 30, State::Stopped)];
        assert_eq!(b.free_ram_mb(&busy), 24576 - 4096, "a stopped workload holds no RAM");
        assert_eq!(b.free_disk_gb(&busy), 880 - 80, "a stopped workload still holds its disk");
    }

    #[test]
    fn allowances_cap_and_nothing_goes_negative() {
        let b = SpaceBudget { ram_allowance_mb: Some(20000), disk_allowance_gb: Some(300), reserve_ram_mb: 4000, reserve_disk_gb: 50, margin_disk_gb: 10, ..SpaceBudget::new(65536, 2000) };
        assert_eq!((b.free_ram_mb(&[]), b.free_disk_gb(&[])), (16000, 240));
        let huge = SpaceBudget { ram_allowance_mb: Some(99999), disk_allowance_gb: Some(99999), reserve_ram_mb: 0, reserve_disk_gb: 0, margin_disk_gb: 0, ..SpaceBudget::new(1000, 100) };
        assert_eq!((huge.free_ram_mb(&[]), huge.free_disk_gb(&[])), (1000, 100));
        let over = SpaceBudget { reserve_ram_mb: 2000, reserve_disk_gb: 500, margin_disk_gb: 0, ..SpaceBudget::new(1000, 100) };
        assert_eq!((over.free_ram_mb(&[]), over.free_disk_gb(&[])), (0, 0));
    }

    #[test]
    fn refusals_carry_the_numbers() {
        let b = SpaceBudget { reserve_ram_mb: 2048, reserve_disk_gb: 40, margin_disk_gb: 10, ..SpaceBudget::new(10240, 200) };
        assert!(b.check(&request(8192, 150, Kind::Vm, GpuMode::None), &[], &ALL, None).is_ok());
        let ram = b.check(&request(8193, 1, Kind::Vm, GpuMode::None), &[], &ALL, None).unwrap_err();
        assert_eq!((ram.resource, ram.needed, ram.free), ("ram_mb", 8193, 8192));
        let disk = b.check(&request(512, 151, Kind::Vm, GpuMode::None), &[], &ALL, None).unwrap_err();
        assert_eq!((disk.resource, disk.free), ("disk_gb", 150));
    }

    #[test]
    fn the_real_disk_can_only_make_it_stricter() {
        let b = SpaceBudget { reserve_ram_mb: 0, reserve_disk_gb: 0, margin_disk_gb: 20, ..SpaceBudget::new(10240, 1000) };
        let r = request(512, 100, Kind::Vm, GpuMode::None);
        assert!(b.check(&r, &[], &ALL, Some(500)).is_ok());
        assert_eq!(b.check(&r, &[], &ALL, Some(110)).unwrap_err().free, 90);
    }

    #[test]
    fn capabilities_are_checked() {
        let b = SpaceBudget::new(65536, 2000);
        let no_vm = Capabilities { vm: false, ..ALL };
        let no_container = Capabilities { container: false, ..ALL };
        for (r, caps) in [
            (request(512, 1, Kind::Vm, GpuMode::None), no_vm), (request(512, 1, Kind::Container, GpuMode::None), no_container),
            (request(512, 1, Kind::Vm, GpuMode::Passthrough), ALL), (request(512, 1, Kind::Vm, GpuMode::Container), ALL),
            (request(512, 1, Kind::Container, GpuMode::Passthrough), Capabilities { gpu_in_vm: true, ..ALL }),
        ] {
            assert_eq!(b.check(&r, &[], &caps, None).unwrap_err().code, "missing_capability");
        }
        assert!(b.check(&request(512, 1, Kind::Container, GpuMode::Container), &[], &ALL, None).is_ok());
    }
}
