//! The space budget kept in step with the machine: its totals are read again before every decision, because a volume can grow or shrink while the Agent runs.
use crate::budget::SpaceBudget;
use std::sync::Mutex;

/// One fresh look at the machine. RAM in MB, disk in GB.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Reading {
    pub ram_total_mb: u64,
    pub disk_total_gb: u64,
    pub disk_available_gb: u64,
}

type Reader = Box<dyn Fn() -> Option<Reading> + Send + Sync>;

/// What a refresh gives back: the budget to decide with, and what the file system says is free (None when the read failed).
pub struct Current {
    pub budget: SpaceBudget,
    pub os_available_disk_gb: Option<u64>,
}

pub struct LiveSpace {
    budget: Mutex<SpaceBudget>,
    reader: Reader,
}

/// A reading with a zero total is a failed read in disguise; it never replaces good numbers.
fn usable(reading: Option<Reading>) -> Option<Reading> {
    reading.filter(|r| r.ram_total_mb > 0 && r.disk_total_gb > 0)
}

/// Pure: the budget after a reading. A missing or unusable reading changes nothing.
pub fn after_reading(budget: &SpaceBudget, reading: Option<Reading>) -> SpaceBudget {
    match usable(reading) {
        Some(r) => budget.with_totals(r.ram_total_mb, r.disk_total_gb),
        None => budget.clone(),
    }
}

impl LiveSpace {
    pub fn new(budget: SpaceBudget, reader: impl Fn() -> Option<Reading> + Send + Sync + 'static) -> Self {
        LiveSpace { budget: Mutex::new(budget), reader: Box::new(reader) }
    }

    /// Reads the machine (blocking, cheap) and updates the budget in place.
    pub fn refresh(&self) -> Current {
        let reading = usable((self.reader)());
        let mut guard = self.budget.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        *guard = after_reading(&guard, reading);
        Current { budget: guard.clone(), os_available_disk_gb: reading.map(|r| r.disk_available_gb) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{GpuMode, Kind, State, Workload};
    use std::sync::Arc;

    fn workload(disk: u64, state: State) -> Workload {
        Workload { id: "w".into(), name: "n".into(), kind: Kind::Vm, state, cpu: 1, ram_mb: 1024, disk_gb: disk, gpu_mode: GpuMode::None, address: None, bundle_version: None }
    }

    fn reading(ram: u64, disk: u64) -> Option<Reading> {
        Some(Reading { ram_total_mb: ram, disk_total_gb: disk, disk_available_gb: disk / 2 })
    }

    const RAM: u64 = 65536;

    #[test]
    fn disk_total_follows_a_volume_that_grew_while_running() {
        let start = SpaceBudget::new(RAM, 105);
        assert_eq!((start.reserve_disk_gb, start.free_disk_gb(&[])), (30, 55));
        let grown = after_reading(&start, reading(RAM, 981));
        assert_eq!((grown.disk_total_gb, grown.reserve_disk_gb), (981, 196));
        assert_eq!(grown.free_disk_gb(&[]), 981 - 196 - 20);
        let held = [workload(50, State::Running), workload(30, State::Stopped)];
        assert_eq!(grown.free_disk_gb(&held), 981 - 196 - 20 - 80, "a stopped workload still holds its disk");
    }

    #[test]
    fn ram_total_follows_the_same_way() {
        let grown = after_reading(&SpaceBudget::new(16384, 500), reading(65536, 500));
        assert_eq!((grown.ram_total_mb, grown.reserve_ram_mb), (65536, 16384));
    }

    #[test]
    fn an_explicit_allowance_is_kept_and_clamped_to_the_new_total() {
        let set = SpaceBudget { disk_allowance_gb: Some(300), ..SpaceBudget::new(RAM, 105) };
        assert_eq!(after_reading(&set, reading(RAM, 981)).free_disk_gb(&[]), 300 - 196 - 20);
        let shrunk = after_reading(&set, reading(RAM, 200));
        assert_eq!(shrunk.free_disk_gb(&[]), 200 - 40 - 20, "the allowance cannot exceed the new total");
    }

    #[test]
    fn an_explicit_reserve_stays_while_a_default_one_moves() {
        let pinned = SpaceBudget { reserve_disk_gb: 77, reserve_disk_pinned: true, reserve_ram_mb: 5000, reserve_ram_pinned: true, ..SpaceBudget::new(RAM, 105) };
        let grown = after_reading(&pinned, reading(131072, 981));
        assert_eq!((grown.reserve_disk_gb, grown.reserve_ram_mb), (77, 5000));
        let half = SpaceBudget { reserve_disk_gb: 77, reserve_disk_pinned: true, ..SpaceBudget::new(RAM, 105) };
        assert_eq!(after_reading(&half, reading(131072, 981)).reserve_ram_mb, 32768);
    }

    #[test]
    fn a_failed_read_keeps_the_last_good_numbers() {
        let start = SpaceBudget::new(RAM, 981);
        for bad in [None, reading(0, 981), reading(RAM, 0), reading(0, 0)] {
            assert_eq!(after_reading(&start, bad), start);
        }
    }

    #[test]
    fn the_live_budget_follows_a_reader_that_changes_and_survives_a_failure() {
        let readings = Arc::new(Mutex::new(vec![reading(RAM, 981), None, reading(RAM, 105)]));
        let feed = readings.clone();
        let space = LiveSpace::new(SpaceBudget::new(RAM, 105), move || feed.lock().unwrap().remove(0));
        let first = space.refresh();
        assert_eq!((first.budget.disk_total_gb, first.os_available_disk_gb), (981, Some(490)));
        let failed = space.refresh();
        assert_eq!((failed.budget.disk_total_gb, failed.os_available_disk_gb), (981, None));
        assert_eq!(space.refresh().budget.disk_total_gb, 105);
    }
}
